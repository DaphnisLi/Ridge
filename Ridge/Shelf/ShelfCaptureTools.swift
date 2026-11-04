import AppKit
import Foundation

/// 货架剪贴板栏的取色 / OCR：结果写入系统剪贴板，由 `ClipboardHistoryStore` 归档。
@MainActor
final class ShelfCaptureTools {
    static let shared = ShelfCaptureTools()

    private var colorSampler: NSColorSampler?
    private var isBusy = false

    private init() {}

    /// 上一轮若 Esc 失效等导致卡在 busy，点按钮时强制清掉再开新的。
    private func forceResetIfBusy(reason: String) {
        guard isBusy else { return }
        AppLog.warn("ShelfCapture", "采集仍忙碌，强制复位后再开始", ["reason": reason])
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
        AppLog.info("ShelfCapture", "开始系统屏幕取色")

        IslandController.shared?.beginExternalPointerTool(reason: "shelfColorPick")
        IslandNoticeCenter.shared.present(.colorPickTip)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let sampler = NSColorSampler()
            self.colorSampler = sampler
            sampler.show { [weak self] color in
                DispatchQueue.main.async {
                    self?.finishColorPick(color)
                }
            }
        }
    }

    private func finishColorPick(_ color: NSColor?) {
        colorSampler = nil
        IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.colorPickTipID)
        Self.terminateStrayColorSampler(reason: "finish")

        if let color {
            let hex = Self.hexString(from: color)
            let board = NSPasteboard.general
            board.clearContents()
            board.writeObjects([color])
            board.setString(hex, forType: .string)
            AppLog.info("ShelfCapture", "取色完成并写入剪贴板", ["hex": hex])
        } else {
            AppLog.info("ShelfCapture", "取色已取消")
            if IslandController.shared?.isHoveringIsland != true {
                IslandController.shared?.collapse(reason: "shelfColorPickCancelled")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            Self.terminateStrayColorSampler(reason: "finishDelayed")
            IslandController.shared?.endExternalPointerTool(reason: "shelfColorPickDone")
            self?.isBusy = false
        }
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
        AppLog.info("ShelfCapture", "开始屏幕 OCR 框选")
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
                AppLog.info("ShelfCapture", "OCR 完成并写入剪贴板", [
                    "chars": trimmed.count,
                    "preview": String(trimmed.prefix(48))
                ])
            }
        case .failure(let error):
            switch error {
            case .cancelled:
                AppLog.info("ShelfCapture", "OCR 已取消")
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
