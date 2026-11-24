import Combine
import Foundation

@MainActor
final class AirDropReceiveSettings: ObservableObject {
    static let shared = AirDropReceiveSettings()

    private enum Key {
        static let clickAction = "airDropReceive.clickAction.v1"
    }

    @Published var clickAction: AirDropReceiveClickAction {
        didSet {
            guard clickAction != oldValue else { return }
            UserDefaults.standard.set(clickAction.rawValue, forKey: Key.clickAction)
            AppLog.info("AirDrop", "点击动作已改", ["action": clickAction.rawValue])
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Key.clickAction)
        clickAction = AirDropReceiveClickAction(rawValue: raw ?? "") ?? .openWithDefaultApp
    }

    func restoreDefaults() {
        clickAction = .openWithDefaultApp
        AppLog.info("AirDrop", "已恢复默认点击动作")
    }
}
