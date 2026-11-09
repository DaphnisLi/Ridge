import AppKit
import Carbon.HIToolbox
import Foundation

/// 系统级快捷键注册（Carbon `RegisterEventHotKey`）。不依赖输入监控权限。
@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    fileprivate struct Entry {
        var chord: HotKeyChord
        var hotKeyRef: EventHotKeyRef?
        var handler: () -> Void
        var carbonID: UInt32
    }

    fileprivate var entries: [String: Entry] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextCarbonID: UInt32 = 1
    private let signature: OSType = 0x5264_6745 // 'RdgE'

    private init() {
        installHandlerIfNeeded()
    }

    func register(id: String, chord: HotKeyChord, handler: @escaping () -> Void) {
        unregister(id: id)
        guard chord.hasModifiers else {
            AppLog.warn("HotKey", "拒绝无修饰键快捷键", ["id": id, "chord": chord.displayString])
            return
        }

        let carbonID = nextCarbonID
        nextCarbonID += 1
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: carbonID)
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            AppLog.error("HotKey", "RegisterEventHotKey 失败", [
                "id": id,
                "chord": chord.displayString,
                "status": Int(status)
            ])
            return
        }
        entries[id] = Entry(chord: chord, hotKeyRef: hotKeyRef, handler: handler, carbonID: carbonID)
        AppLog.warn("HotKey", "已注册全局快捷键", [
            "id": id,
            "chord": chord.displayString,
            "carbonID": Int(carbonID)
        ])
    }

    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if let ref = entry.hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        AppLog.warn("HotKey", "已注销全局快捷键", [
            "id": id,
            "chord": entry.chord.displayString
        ])
    }

    func unregisterAll() {
        for id in Array(entries.keys) {
            unregister(id: id)
        }
    }

    fileprivate func invoke(carbonID: UInt32) {
        guard let entry = entries.values.first(where: { $0.carbonID == carbonID }) else {
            AppLog.debug("HotKey", "未找到 carbonID 对应快捷键", ["carbonID": Int(carbonID)])
            return
        }
        AppLog.warn("HotKey", "快捷键触发", ["chord": entry.chord.displayString])
        entry.handler()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            ridgeHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            AppLog.error("HotKey", "InstallEventHandler 失败", ["status": Int(status)])
        } else {
            AppLog.info("HotKey", "全局快捷键事件处理器已安装")
        }
    }
}

private func ridgeHotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr else { return noErr }
    let carbonID = hotKeyID.id
    DispatchQueue.main.async {
        GlobalHotKeyCenter.shared.invoke(carbonID: carbonID)
    }
    return noErr
}
