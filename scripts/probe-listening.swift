#!/usr/bin/env swift
import Foundation
import IOBluetooth
import ObjectiveC

func readByte(_ object: AnyObject, _ name: String) -> UInt64? {
    let sel = NSSelectorFromString(name)
    guard object.responds(to: sel),
          let imp = class_getMethodImplementation(object_getClass(object), sel)
    else { return nil }
    typealias Fn = @convention(c) (AnyObject, Selector) -> UInt64
    return unsafeBitCast(imp, to: Fn.self)(object, sel)
}

func readBool(_ object: AnyObject, _ name: String) -> Bool {
    let sel = NSSelectorFromString(name)
    guard object.responds(to: sel),
          let imp = class_getMethodImplementation(object_getClass(object), sel)
    else { return false }
    typealias Fn = @convention(c) (AnyObject, Selector) -> Int8
    return unsafeBitCast(imp, to: Fn.self)(object, sel) != 0
}

let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
print("paired=\(paired.count)")
for d in paired {
    let name = d.name ?? "?"
    guard name.localizedCaseInsensitiveContains("airpods")
            || name.localizedCaseInsensitiveContains("beats")
            || d.isConnected()
    else { continue }
    print("--- \(name) connected=\(d.isConnected()) addr=\(d.addressString ?? "")")
    print("  anc=\(readBool(d, "isANCSupported")) transparency=\(readBool(d, "isTransparencySupported")) advanced=\(readBool(d, "isAdvancedAppleAudioDevice"))")
    print("  listeningMode=\(String(describing: readByte(d, "listeningMode")))")
    print("  listeningModeConfigs=\(String(describing: readByte(d, "listeningModeConfigs")))")
    print("  listeningServices=\(String(describing: readByte(d, "listeningServices")))")
    print("  inEar=\(readBool(d, "inEar")) primaryInEar=\(String(describing: readByte(d, "primaryInEar"))) secondaryInEar=\(String(describing: readByte(d, "secondaryInEar")))")
    if let v = d.value(forKey: "listeningMode") {
        print("  KVC listeningMode=\(v) type=\(type(of: v))")
    } else {
        print("  KVC listeningMode=nil")
    }
    if let v = d.value(forKey: "listeningServices") {
        print("  KVC listeningServices=\(v) type=\(type(of: v))")
    }
    if let v = d.value(forKey: "reservedMagicSettings") {
        print("  KVC reservedMagicSettings=\(v) type=\(type(of: v))")
    }
}
