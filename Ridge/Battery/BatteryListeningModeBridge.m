#import "BatteryListeningModeBridge.h"
#import <IOBluetooth/IOBluetooth.h>
#import <objc/runtime.h>

@interface IOBluetoothDevice (RidgeListeningModePrivate)
@property(nonatomic) unsigned char listeningMode;
@property(nonatomic) unsigned char listeningModeConfigs;
@property(readonly) BOOL isANCSupported;
@property(readonly) BOOL isTransparencySupported;
- (void)updateFromServer;
@end

@implementation BatteryListeningModeBridge

+ (uint8_t)listeningModeForDevice:(IOBluetoothDevice *)device {
    if (![device respondsToSelector:@selector(listeningMode)]) {
        return 0;
    }
    if ([device respondsToSelector:@selector(updateFromServer)]) {
        [device updateFromServer];
    }
    return (uint8_t)device.listeningMode;
}

+ (uint8_t)listeningModeConfigsForDevice:(IOBluetoothDevice *)device {
    if (![device respondsToSelector:@selector(listeningModeConfigs)]) {
        return 0;
    }
    return (uint8_t)device.listeningModeConfigs;
}

+ (BOOL)isANCSupportedForDevice:(IOBluetoothDevice *)device {
    if (![device respondsToSelector:@selector(isANCSupported)]) {
        return NO;
    }
    return device.isANCSupported;
}

+ (BOOL)isTransparencySupportedForDevice:(IOBluetoothDevice *)device {
    if (![device respondsToSelector:@selector(isTransparencySupported)]) {
        return NO;
    }
    return device.isTransparencySupported;
}

@end
