import Combine
import Foundation

/// 按小组件开关与设置和弦，同步注册取色 / OCR 全局快捷键。
@MainActor
final class CaptureHotKeyCoordinator {
    static let shared = CaptureHotKeyCoordinator()

    static let colorPickHotKeyID = "builtin.colorPick"
    static let ocrSelectHotKeyID = "builtin.ocrSelect"

    private var started = false
    private var observers: Set<AnyCancellable> = []
    private var lastColorEnabled = false
    private var lastOCREnabled = false
    private var lastColorChord: HotKeyChord?
    private var lastOCRChord: HotKeyChord?

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        WidgetSettings.shared.$disabledIDs
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sync(reason: "widgetEnabled")
            }
            .store(in: &observers)

        ColorPickSettings.shared.$hotKey
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sync(reason: "colorPickChord")
            }
            .store(in: &observers)

        OCRSelectSettings.shared.$hotKey
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sync(reason: "ocrSelectChord")
            }
            .store(in: &observers)

        sync(reason: "start")
        AppLog.warn("HotKey", "采集快捷键协调器已启动")
    }

    func sync(reason: String) {
        let widgets = WidgetSettings.shared
        let hotKeys = GlobalHotKeyCenter.shared
        var changed = false

        let colorEnabled = widgets.isEnabled(Self.colorPickHotKeyID)
        let colorChord = ColorPickSettings.shared.hotKey
        if colorEnabled {
            if !lastColorEnabled || lastColorChord != colorChord {
                hotKeys.register(id: Self.colorPickHotKeyID, chord: colorChord) {
                    ShelfCaptureTools.shared.beginColorPick()
                }
                lastColorEnabled = true
                lastColorChord = colorChord
                changed = true
            }
        } else if lastColorEnabled {
            hotKeys.unregister(id: Self.colorPickHotKeyID)
            lastColorEnabled = false
            lastColorChord = nil
            changed = true
        }

        let ocrEnabled = widgets.isEnabled(Self.ocrSelectHotKeyID)
        let ocrChord = OCRSelectSettings.shared.hotKey
        if ocrEnabled {
            if !lastOCREnabled || lastOCRChord != ocrChord {
                hotKeys.register(id: Self.ocrSelectHotKeyID, chord: ocrChord) {
                    ShelfCaptureTools.shared.beginOCR()
                }
                lastOCREnabled = true
                lastOCRChord = ocrChord
                changed = true
            }
        } else if lastOCREnabled {
            hotKeys.unregister(id: Self.ocrSelectHotKeyID)
            lastOCREnabled = false
            lastOCRChord = nil
            changed = true
        }

        if changed {
            AppLog.warn("HotKey", "采集快捷键已同步", [
                "reason": reason,
                "colorPick": colorEnabled,
                "ocrSelect": ocrEnabled,
                "colorChord": colorChord.displayString,
                "ocrChord": ocrChord.displayString
            ])
        } else {
            AppLog.debug("HotKey", "采集快捷键无变化", ["reason": reason])
        }
    }
}
