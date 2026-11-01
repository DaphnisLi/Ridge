import CoreAudio
import Foundation

enum CoreAudioProperty {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func size(
        object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> UInt32? {
        var address = Self.address(selector, scope: scope, element: element)
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &dataSize)
        guard status == noErr else { return nil }
        return dataSize
    }

    static func get<T>(
        object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> T? {
        var address = Self.address(selector, scope: scope, element: element)
        var dataSize = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, pointer)
        guard status == noErr else { return nil }
        return pointer.pointee
    }

    static func getArray<T>(
        object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> [T] {
        guard let dataSize = size(object: object, selector, scope: scope, element: element), dataSize > 0 else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<T>.size
        guard count > 0 else { return [] }
        var address = Self.address(selector, scope: scope, element: element)
        var mutableSize = dataSize
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { pointer.deallocate() }
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &mutableSize, pointer)
        guard status == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    static func getCFString(
        object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var address = Self.address(selector, scope: scope)
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    @discardableResult
    static func set<T>(
        object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        value: T
    ) -> Bool {
        var address = Self.address(selector, scope: scope, element: element)
        var mutable = value
        let status = AudioObjectSetPropertyData(
            object,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<T>.size),
            &mutable
        )
        return status == noErr
    }

    @discardableResult
    static func addListener(
        object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        queue: DispatchQueue = .main,
        block: @escaping () -> Void
    ) -> AudioObjectPropertyListenerBlock? {
        var address = Self.address(selector, scope: scope, element: element)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            queue.async { block() }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, listener)
        guard status == noErr else { return nil }
        return listener
    }

    static func removeListener(
        object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        queue: DispatchQueue = .main,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = Self.address(selector, scope: scope, element: element)
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
}

extension AudioObjectID {
    static var system: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }
    static var unknown: AudioObjectID { AudioObjectID(kAudioObjectUnknown) }
    var isValid: Bool { self != kAudioObjectUnknown && self != 0 }
}
