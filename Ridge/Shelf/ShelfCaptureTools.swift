import AppKit
import Foundation

/// 取色 / OCR：结果始终写入系统剪贴板；可选再进 `ClipboardHistoryStore` 历史。
@MainActor
final class ShelfCaptureTools {
    static let shared = ShelfCaptureTools()

    private var colorSampler: NSColorSampler?
    private var isBusy = false
    private var colorPickLocalEscMonitor: Any?
    private var colorPickGlobalEscMonitor: Any?
    private var colorPickWatchdog: DispatchWorkItem?
    private var showWorkItem: DispatchWorkItem?

    /// 系统取色器若未回调，超时强制退出，避免 `isExternalPointerToolActive` 永久穿透假死。
    private static let colorPickTimeoutSeconds: TimeInterval = 30
    /// 成功写入后短暂压制剪贴板轮询的重复「已复制」，避免连闪两次。
    private static var suppressClipboardCopiedNoticeUntil: Date = .distantPast

    private init() {}

    static var shouldSuppressClipboardCopiedNotice: Bool {
        Date() < suppressClipboardCopiedNoticeUntil
    }

    /// 上一轮若 Esc 失效等导致卡在 busy，点按钮时强制清掉再开新的。
    private func forceResetIfBusy(reason: String) {
        guard isBusy else { return }
        AppLog.warn("ShelfCapture", "采集仍忙碌，强制复位后再开始", ["reason": reason])
        showWorkItem?.cancel()
        showWorkItem = nil
        tearDownColorPickGuards(reason: "forceReset:\(reason)")
        colorSampler = nil
        ScreenRegionOCRController.shared.cancel()
        IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.colorPickTipID)
        IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.ocrSelectTipID)
        // 仅卡死复位时清理残留进程；成功路径绝不强杀，否则下次放大镜起不来。
        Self.terminateStrayColorSampler(reason: "forceReset")
        IslandController.shared?.endExternalPointerTool(reason: "forceReset:\(reason)")
        isBusy = false
    }

    // MARK: - Color

    func beginColorPick() {
        guard WidgetSettings.shared.isEnabled(ColorPickWidget.manifest.id) else {
            AppLog.warn("ShelfCapture", "取色已关闭，忽略唤醒")
            return
        }
        forceResetIfBusy(reason: "colorPick")
        isBusy = true
        AppLog.warn("ShelfCapture", "开始系统屏幕取色")

        IslandController.shared?.beginExternalPointerTool(reason: "shelfColorPick")
        installColorPickEscapeMonitors()

        // 先收岛落稳，再 show；引导 tip 延后到 loupe 出现之后，避免 expand 抢层把放大镜掐掉。
        showWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isBusy else {
                AppLog.warn("ShelfCapture", "取色已取消，跳过 NSColorSampler.show")
                return
            }
            let sampler = NSColorSampler()
            self.colorSampler = sampler
            AppLog.warn("ShelfCapture", "调用 NSColorSampler.show")
            sampler.show { [weak self] color in
                DispatchQueue.main.async {
                    self?.finishColorPick(color)
                }
            }
            // loupe 起来后再挂引导，且不 orderFront 抢层（外部工具态已跳过 activate）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.isBusy, self.colorSampler != nil else { return }
                IslandNoticeCenter.shared.present(.colorPickTip)
                AppLog.warn("ShelfCapture", "取色引导已上岛")
            }
            self.scheduleColorPickWatchdog()
        }
        showWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func finishColorPick(_ color: NSColor?) {
        guard isBusy else {
            AppLog.debug("ShelfCapture", "取色结束忽略：已不在忙碌态")
            return
        }
        isBusy = false
        showWorkItem?.cancel()
        showWorkItem = nil
        tearDownColorPickGuards(reason: "finish")
        // 只释放引用，让系统自行拆除 loupe；禁止 terminate ColorSampler。
        colorSampler = nil

        var copiedHex: String?
        if let color {
            let hex = Self.hexString(from: color)
            let board = NSPasteboard.general
            board.clearContents()
            board.writeObjects([color])
            board.setString(hex, forType: .string)
            copiedHex = hex
            let saveHistory = ColorPickSettings.shared.saveToHistory
            if !saveHistory {
                ClipboardHistoryStore.shared.suppressHistory(
                    forChangeCount: board.changeCount,
                    reason: "colorPick"
                )
            }
            AppLog.warn("ShelfCapture", "取色完成并写入系统剪贴板", [
                "hex": hex,
                "history": saveHistory
            ])
        } else {
            AppLog.warn("ShelfCapture", "取色已取消")
            IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.colorPickTipID)
            if IslandController.shared?.isHoveringIsland != true {
                IslandController.shared?.collapse(reason: "shelfColorPickCancelled")
            }
        }

        // 先结束穿透态；再投「已复制」。present 内会先预备短条尺寸再换皮，避免宽翼卡死。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            IslandController.shared?.endExternalPointerTool(reason: "shelfColorPickDone")
            if let hex = copiedHex {
                Self.presentCopiedSuccess(
                    detail: L10n.Shelf.colorPickDone(hex),
                    category: "color",
                    symbol: "eyedropper"
                )
            }
            // loupe 正常会自拆；若 XPC 残留会整屏吞点击。闲置后再清，勿与进行中的取色撞车。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, !self.isBusy, self.colorSampler == nil else { return }
                Self.terminateStrayColorSampler(reason: "postColorPickIdle")
            }
        }
    }

    private func installColorPickEscapeMonitors() {
        tearDownColorPickGuards(reason: "reinstall")
        colorPickLocalEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            AppLog.warn("ShelfCapture", "本地 Esc 取消取色")
            DispatchQueue.main.async {
                self?.finishColorPick(nil)
            }
            return nil
        }
        colorPickGlobalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            AppLog.warn("ShelfCapture", "全局 Esc 取消取色")
            DispatchQueue.main.async {
                self?.finishColorPick(nil)
            }
        }
    }

    private func scheduleColorPickWatchdog() {
        colorPickWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isBusy else { return }
            AppLog.error("ShelfCapture", "取色超时，强制取消以免岛永久穿透", [
                "seconds": Int(Self.colorPickTimeoutSeconds)
            ])
            self.finishColorPick(nil)
        }
        colorPickWatchdog = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.colorPickTimeoutSeconds,
            execute: work
        )
    }

    private func tearDownColorPickGuards(reason: String) {
        if let local = colorPickLocalEscMonitor {
            NSEvent.removeMonitor(local)
            colorPickLocalEscMonitor = nil
        }
        if let global = colorPickGlobalEscMonitor {
            NSEvent.removeMonitor(global)
            colorPickGlobalEscMonitor = nil
        }
        colorPickWatchdog?.cancel()
        colorPickWatchdog = nil
        AppLog.debug("ShelfCapture", "已拆除取色 Esc/超时守卫", ["reason": reason])
    }

    private static func terminateStrayColorSampler(reason: String) {
        var matched = 0
        for app in NSWorkspace.shared.runningApplications {
            let bid = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? ""
            let exe = app.executableURL?.path ?? ""
            let hit = bid.localizedCaseInsensitiveContains("ColorSampler")
                || name.localizedCaseInsensitiveContains("ColorSampler")
                || exe.localizedCaseInsensitiveContains("ColorSampler")
            guard hit else { continue }
            matched += 1
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !app.isTerminated {
                    app.forceTerminate()
                }
            }
        }
        // ColorSampler.xpc 常不进 runningApplications；残留 loupe 会整屏吞点击。
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["-9", "ColorSampler"]
        do {
            try killall.run()
            killall.waitUntilExit()
            if killall.terminationStatus == 0 {
                matched += 1
            }
        } catch {
            AppLog.debug("ShelfCapture", "killall ColorSampler 调用失败", [
                "error": String(describing: error)
            ])
        }
        guard matched > 0 else { return }
        AppLog.warn("ShelfCapture", "已清理残留 ColorSampler", [
            "reason": reason,
            "count": matched
        ])
    }

    // MARK: - OCR

    func beginOCR() {
        guard WidgetSettings.shared.isEnabled(OCRSelectWidget.manifest.id) else {
            AppLog.warn("ShelfCapture", "框选文字提取已关闭，忽略唤醒")
            return
        }
        forceResetIfBusy(reason: "ocr")

        if !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            AppLog.warn("ShelfCapture", "OCR 需要屏幕录制权限", ["granted": granted])
            if !granted {
                IslandNoticeCenter.shared.present(
                    .clipboardCaptureHint(
                        id: "ocr.permission",
                        text: L10n.Shelf.ocrNeedScreenCapture,
                        symbol: "text.viewfinder"
                    )
                )
                return
            }
        }

        isBusy = true
        AppLog.warn("ShelfCapture", "开始屏幕 OCR 框选")
        IslandController.shared?.beginExternalPointerTool(reason: "shelfOCR")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            guard self.isBusy else {
                AppLog.warn("ShelfCapture", "OCR 已取消，跳过框选层")
                return
            }
            ScreenRegionOCRController.shared.begin { [weak self] result in
                DispatchQueue.main.async {
                    self?.finishOCR(result)
                }
            }
            IslandNoticeCenter.shared.present(.ocrSelectTip)
            AppLog.warn("ShelfCapture", "OCR 框选引导已上岛")
        }
    }

    private func finishOCR(_ result: Result<String, ScreenRegionOCRController.OCRError>) {
        var copiedDetail: String?
        var shouldDismissTip = true
        let prefs = OCRSelectSettings.shared
        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                AppLog.warn("ShelfCapture", "OCR 无文字")
                IslandNoticeCenter.shared.present(
                    .clipboardCaptureHint(
                        id: "ocr.empty",
                        text: L10n.Shelf.ocrEmpty,
                        symbol: "text.viewfinder"
                    )
                )
                shouldDismissTip = false
            } else {
                let preview = String(trimmed.prefix(28))
                let board = NSPasteboard.general
                board.clearContents()
                board.setString(trimmed, forType: .string)
                if !prefs.saveToHistory {
                    ClipboardHistoryStore.shared.suppressHistory(
                        forChangeCount: board.changeCount,
                        reason: "ocrSelect"
                    )
                }
                copiedDetail = L10n.Shelf.ocrDone(preview)
                // 成功时留着 tip，下面用「已复制」替换，避免先收岛。
                shouldDismissTip = false
                AppLog.warn("ShelfCapture", "OCR 完成并写入系统剪贴板", [
                    "chars": trimmed.count,
                    "preview": String(trimmed.prefix(48)),
                    "history": prefs.saveToHistory
                ])
            }
        case .failure(let error):
            switch error {
            case .cancelled:
                AppLog.warn("ShelfCapture", "OCR 已取消")
                if IslandController.shared?.isHoveringIsland != true {
                    IslandController.shared?.collapse(reason: "shelfOCRCancelled")
                }
            case .captureFailed:
                AppLog.error("ShelfCapture", "OCR 截屏失败")
                IslandNoticeCenter.shared.present(
                    .clipboardCaptureHint(
                        id: "ocr.capture",
                        text: L10n.Shelf.ocrCaptureFailed,
                        symbol: "text.viewfinder"
                    )
                )
                shouldDismissTip = false
            case .recognitionFailed:
                AppLog.error("ShelfCapture", "OCR 识别失败")
                IslandNoticeCenter.shared.present(
                    .clipboardCaptureHint(
                        id: "ocr.recognize",
                        text: L10n.Shelf.ocrFailed,
                        symbol: "text.viewfinder"
                    )
                )
                shouldDismissTip = false
            }
        }

        if shouldDismissTip {
            IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.ocrSelectTipID)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            IslandController.shared?.endExternalPointerTool(reason: "shelfOCRDone")
            self?.isBusy = false
            if let detail = copiedDetail {
                Self.presentCopiedSuccess(
                    detail: detail,
                    category: "text",
                    symbol: "text.viewfinder"
                )
            }
        }
    }

    /// 取色 / OCR 成功后的「已复制」短提示；须在 `endExternalPointerTool` 之后调用。
    /// 若引导 tip 仍在，直接替换（不先 dismiss 收岛）。
    /// 翼引导→短条依赖 `prepareShortNoticeLayout` + 误缩守卫翼→短放行（shelf-copied-notice-miss）。
    private static func presentCopiedSuccess(detail: String, category: String, symbol: String) {
        guard ShelfSettings.shared.showCopiedNotice else {
            IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.colorPickTipID)
            IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.ocrSelectTipID)
            AppLog.debug("ShelfCapture", "复制提示已关闭，跳过上岛", ["category": category])
            return
        }
        let previous = IslandNoticeCenter.shared.current
        suppressClipboardCopiedNoticeUntil = Date().addingTimeInterval(1.2)
        let tipID = "copy.\(category).\(UUID().uuidString)"
        IslandNoticeCenter.shared.present(
            .clipboardCaptureHint(id: tipID, text: detail, symbol: symbol)
        )
        AppLog.warn("ShelfCapture", "已投递复制成功提示", [
            "category": category,
            "detail": String(detail.prefix(48)),
            "replacedWing": previous?.usesNotchWingChrome == true,
            "prev": previous?.id ?? "",
            "tip": tipID
        ])
    }

    private static func hexString(from color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
