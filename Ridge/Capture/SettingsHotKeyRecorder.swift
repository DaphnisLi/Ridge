import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 设置页快捷键录制行：点按录制 → 下一组键落盘；Esc 取消；与其它 Ridge 快捷键冲突则拒绝并提示。
struct SettingsHotKeyRecorder: View {
    @Binding var chord: HotKeyChord
    /// 当前编辑归属，用于冲突检查时排除自身。
    var owner: HotKeyOwnerID
    var title: String
    var subtitle: String? = nil

    @State private var isRecording = false
    @State private var monitor: Any?
    /// 刚录到冲突时的瞬时提示（未改 chord）。
    @State private var rejectedConflictMessage: String?

    // 其它功能改快捷键时，本行冲突条须即时刷新。
    @ObservedObject private var colorPickSettings = ColorPickSettings.shared
    @ObservedObject private var ocrSelectSettings = OCRSelectSettings.shared
    @ObservedObject private var downloadCompleteSettings = DownloadCompleteSettings.shared

    private var occupiedByOther: HotKeyOwnerID? {
        _ = colorPickSettings.hotKey
        _ = ocrSelectSettings.hotKey
        _ = downloadCompleteSettings.hotKey
        return HotKeyOwnerID.conflict(for: chord, excluding: owner)
    }

    private var conflictBanner: String? {
        if let rejectedConflictMessage { return rejectedConflictMessage }
        if let other = occupiedByOther {
            return L10n.HotKey.conflictWith(other.displayName)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SettingsChrome.Font.rowTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    if let subtitle {
                        Text(subtitle)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    if isRecording {
                        stopRecording(commit: nil)
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(isRecording ? L10n.HotKey.recording : chord.displayString)
                        .font(SettingsChrome.Font.monoValue)
                        .foregroundStyle(buttonForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(buttonFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(buttonStroke, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(isRecording ? L10n.HotKey.recordingHelp : L10n.HotKey.recordHelp)
            }

            if let conflictBanner {
                Text(conflictBanner)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(conflictBanner)
            }
        }
        .onDisappear {
            stopRecording(commit: nil)
        }
        .onChange(of: chord) { _, _ in
            rejectedConflictMessage = nil
        }
    }

    private var buttonForeground: Color {
        if isRecording { return SettingsChrome.primary }
        if conflictBanner != nil { return SettingsChrome.error }
        return SettingsChrome.onSurface
    }

    private var buttonFill: Color {
        if isRecording { return SettingsChrome.primary.opacity(0.12) }
        if conflictBanner != nil { return SettingsChrome.error.opacity(0.10) }
        return SettingsChrome.surfaceContainer
    }

    private var buttonStroke: Color {
        if isRecording { return SettingsChrome.primary.opacity(0.45) }
        if conflictBanner != nil { return SettingsChrome.error.opacity(0.45) }
        return SettingsChrome.cardStroke
    }

    private func startRecording() {
        stopRecording(commit: nil)
        rejectedConflictMessage = nil
        isRecording = true
        AppLog.warn("HotKey", "开始录制快捷键", ["owner": owner.rawValue])
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async {
                    stopRecording(commit: nil)
                    AppLog.warn("HotKey", "录制已取消（Esc）", ["owner": owner.rawValue])
                }
                return nil
            }
            guard let next = HotKeyChord.from(nsEvent: event) else { return event }
            guard next.hasModifiers else {
                AppLog.debug("HotKey", "录制忽略：缺少修饰键", ["owner": owner.rawValue])
                return nil
            }
            DispatchQueue.main.async {
                stopRecording(commit: next)
            }
            return nil
        }
    }

    private func stopRecording(commit: HotKeyChord?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        let wasRecording = isRecording
        isRecording = false
        guard let commit else {
            if wasRecording {
                AppLog.debug("HotKey", "录制结束未提交", ["owner": owner.rawValue])
            }
            return
        }
        if let other = HotKeyOwnerID.conflict(for: commit, excluding: owner) {
            rejectedConflictMessage = L10n.HotKey.conflictRejected(other.displayName)
            AppLog.warn("HotKey", "快捷键冲突，未保存", [
                "owner": owner.rawValue,
                "chord": commit.displayString,
                "occupiedBy": other.rawValue
            ])
            return
        }
        rejectedConflictMessage = nil
        chord = commit
        AppLog.warn("HotKey", "快捷键已录制", [
            "owner": owner.rawValue,
            "chord": commit.displayString
        ])
    }
}
