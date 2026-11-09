import AppKit
import Foundation

/// 货架剪贴板栏的取色 / OCR：结果写入系统剪贴板，由 `ClipboardHistoryStore` 归档。
@MainActor
final class ShelfCaptureTools {
    static let shared = ShelfCaptureTools()

    private var colorSampler: NSColorSampler?
    private var isBusy = false
    private var colorPickLocalEscMonitor: Any?
    private var colorPickGlobalEscMonitor: Any?
    private var colorPickWatchdog: DispatchWorkItem?

    /// 系统取色器若未回调，超时强制退出，避免 `isExternalPointerToolActive` 永久穿透假死。
    private static let colorPickTimeoutSeconds: TimeInterval = 30

    private init() {}

    /// 上一轮若 Esc 失效等导致卡在 busy，点按钮时强制清掉再开新的。
    private func forceResetIfBusy(reason: String) {
        guard isBusy else { return }
        AppLog.warn("ShelfCapture", "采集仍忙碌，强制复位后再开始", ["reason": reason])
        tearDownColorPickGuards(reason: "forceReset:\(reason)")
        colorSampler = nil
        ScreenRegionOCRController.shared.cancel()
        IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.colorPickTipID)
        Self.terminateStrayColorSampler(reason: "forceReset")
        IslandController.shared?.endExternalPointerTool(reason: "forceReset:\(reason)")
        isBusy = false
    }

    // MARK: - Color

    func beginColorPick() {
        forceResetIfBusy(reason: "colorPick")
        isBusy = true
        AppLog.warn("ShelfCapture", "开始系统屏幕取色")

        IslandController.shared?.beginExternalPointerTool(reason: "shelfColorPick")
        installColorPickEscapeMonitors()

        // 先等收岛/穿透落稳，再 show；引导条放到 show 之后，避免 tip expand 抢前台掐死 Sampler。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
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
            IslandNoticeCenter.shared.present(.colorPickTip)
            self.scheduleColorPickWatchdog()
        }
    }

    private func finishColorPick(_ color: NSColor?) {
        guard isBusy else {
            AppLog.debug("ShelfCapture", "取色结束忽略：已不在忙碌态")
            return
        }
        isBusy = false
        tearDownColorPickGuards(reason: "finish")
        colorSampler = nil
        IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.colorPickTipID)
        Self.terminateStrayColorSampler(reason: "finish")

        if let color {
            let hex = Self.hexString(from: color)
            let board = NSPasteboard.general
            board.clearContents()
            board.writeObjects([color])
            board.setString(hex, forType: .string)
            AppLog.warn("ShelfCapture", "取色完成并写入剪贴板", ["hex": hex])
        } else {
            AppLog.warn("ShelfCapture", "取色已取消")
            if IslandController.shared?.isHoveringIsland != true {
                IslandController.shared?.collapse(reason: "shelfColorPickCancelled")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.terminateStrayColorSampler(reason: "finishDelayed")
            IslandController.shared?.endExternalPointerTool(reason: "shelfColorPickDone")
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
        // 岛已 resignKey / accessory 时本地监听收不到；有输入监控权限时作兜底。
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
        let matches = NSWorkspace.shared.runningApplications.filter { app in
            let bid = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? ""
            return bid.localizedCaseInsensitiveContains("ColorSampler")
                || name.localizedCaseInsensitiveContains("ColorSampler")
        }
        guard !matches.isEmpty else { return }
        for app in matches {
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !app.isTerminated {
                    app.forceTerminate()
                }
            }
        }
        AppLog.warn("ShelfCapture", "已清理残留 ColorSampler", [
            "reason": reason,
            "count": matches.count
        ])
    }

    // MARK: - OCR

    func beginOCR() {
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
            ScreenRegionOCRController.shared.begin { [weak self] result in
                DispatchQueue.main.async {
                    self?.finishOCR(result)
                }
            }
        }
    }

    private func finishOCR(_ result: Result<String, ScreenRegionOCRController.OCRError>) {
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
            } else {
                let board = NSPasteboard.general
                board.clearContents()
                board.setString(trimmed, forType: .string)
                AppLog.warn("ShelfCapture", "OCR 完成并写入剪贴板", [
                    "chars": trimmed.count,
                    "preview": String(trimmed.prefix(48))
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
            case .recognitionFailed:
                AppLog.error("ShelfCapture", "OCR 识别失败")
                IslandNoticeCenter.shared.present(
                    .clipboardCaptureHint(
                        id: "ocr.recognize",
                        text: L10n.Shelf.ocrFailed,
                        symbol: "text.viewfinder"
                    )
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            IslandController.shared?.endExternalPointerTool(reason: "shelfOCRDone")
            self?.isBusy = false
        }
    }

    private static func hexString(from color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
