import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 设置页快捷键录制行：点按录制 → 下一组键落盘；Esc 取消；可选清除。
struct SettingsHotKeyRecorder: View {
    @Binding var chord: HotKeyChord
    var title: String
    var subtitle: String? = nil

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
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
                    .foregroundStyle(
                        isRecording ? SettingsChrome.primary : SettingsChrome.onSurface
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isRecording
                                    ? SettingsChrome.primary.opacity(0.12)
                                    : SettingsChrome.surfaceContainer
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        isRecording
                                            ? SettingsChrome.primary.opacity(0.45)
                                            : SettingsChrome.cardStroke,
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
            .help(isRecording ? L10n.HotKey.recordingHelp : L10n.HotKey.recordHelp)
        }
        .onDisappear {
            stopRecording(commit: nil)
        }
    }

    private func startRecording() {
        stopRecording(commit: nil)
        isRecording = true
        AppLog.warn("HotKey", "开始录制快捷键")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async {
                    stopRecording(commit: nil)
                    AppLog.warn("HotKey", "录制已取消（Esc）")
                }
                return nil
            }
            guard let next = HotKeyChord.from(nsEvent: event) else { return event }
            guard next.hasModifiers else {
                AppLog.debug("HotKey", "录制忽略：缺少修饰键")
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
        if let commit {
            chord = commit
            AppLog.warn("HotKey", "快捷键已录制", ["chord": commit.displayString])
        } else if wasRecording {
            AppLog.debug("HotKey", "录制结束未提交")
        }
    }
}
