import SwiftUI

/// 「电量与外设」实况预览：告警开关在 `builtin.peripheralTip`（外设提示）配置。
struct BatteryWidgetConfigSection: View {
    @ObservedObject private var session = BatterySession.shared

    var body: some View {
        SettingsIslandPreviewCard(widgetID: "system.controlDeck.battery")
            .onAppear {
                session.start()
                session.refresh(reason: "batteryConfigAppear")
                AppLog.info("Battery", "电量实况配置页已显示", [
                    "devices": session.devices.count
                ])
            }
    }
}
