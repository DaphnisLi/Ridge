#import <Foundation/Foundation.h>

@class IOBluetoothDevice;

NS_ASSUME_NONNULL_BEGIN

/// 用 ObjC 消息派发读私有 `listeningMode` / 能力位，避免 Swift IMP 截断。
@interface BatteryListeningModeBridge : NSObject

+ (uint8_t)listeningModeForDevice:(IOBluetoothDevice *)device;
+ (uint8_t)listeningModeConfigsForDevice:(IOBluetoothDevice *)device;
+ (BOOL)isANCSupportedForDevice:(IOBluetoothDevice *)device;
+ (BOOL)isTransparencySupportedForDevice:(IOBluetoothDevice *)device;

@end

NS_ASSUME_NONNULL_END
