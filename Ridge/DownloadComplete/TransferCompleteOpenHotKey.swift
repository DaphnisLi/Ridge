import Foundation

/// 下载完成态全局快捷键（`DownloadCompleteSettings.hotKey`）。
@MainActor
enum TransferCompleteOpenHotKey {
    private static let hotKeyID = "builtin.downloadComplete.openTransient"
    private static var registeredChord: HotKeyChord?

    static func refresh() {
        let settings = DownloadCompleteSettings.shared
        let downloadReady = DownloadCompleteSession.shared.pending?.phase == .completed
            && DownloadCompleteSession.shared.showsCompactStandby

        guard settings.keyboardShortcutEnabled, downloadReady else {
            uninstall()
            return
        }

        let chord = settings.hotKey
        if registeredChord == chord { return }
        uninstall()
        GlobalHotKeyCenter.shared.register(id: hotKeyID, chord: chord) {
            Task { @MainActor in
                guard DownloadCompleteSession.shared.pending?.phase == .completed else { return }
                AppLog.warn("Download", "全局快捷键打开下载完成项", [
                    "chord": DownloadCompleteSettings.shared.hotKey.displayString
                ])
                _ = DownloadCompleteSession.shared.handleClick()
            }
        }
        registeredChord = chord
        AppLog.warn("Download", "已注册完成态全局快捷键", [
            "chord": chord.displayString
        ])
    }

    private static func uninstall() {
        guard registeredChord != nil else { return }
        GlobalHotKeyCenter.shared.unregister(id: hotKeyID)
        registeredChord = nil
        AppLog.debug("Download", "已注销完成态全局快捷键")
    }
}
