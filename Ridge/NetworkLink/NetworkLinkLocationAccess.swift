import AppKit
import CoreLocation
import Foundation

/// macOS 14+：CoreWLAN `ssid` 需定位服务授权；本类只为触发授权 / 读一次粗略定位以弹出系统对话框，不追踪。
@MainActor
final class NetworkLinkLocationAccess: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NetworkLinkLocationAccess()

    @Published private(set) var status: CLAuthorizationStatus

    private let manager = CLLocationManager()
    /// 防止连点叠多次 `requestLocation`。
    private var isPrompting = false

    private override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        AppLog.warn("NetworkLink", "定位授权状态", [
            "status": Self.describe(status),
            "services": CLLocationManager.locationServicesEnabled()
        ])
    }

    var isAuthorized: Bool {
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    var needsRequest: Bool { status == .notDetermined }

    var isDeniedOrRestricted: Bool {
        switch status {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// 设置页主按钮：尽量弹系统授权；弹不出或已拒绝则打开「定位服务」。
    func requestAccessFromSettings() {
        status = manager.authorizationStatus
        AppLog.warn("NetworkLink", "设置页点击定位授权", [
            "status": Self.describe(status),
            "services": CLLocationManager.locationServicesEnabled()
        ])
        if isAuthorized {
            NetworkLinkSession.shared.refresh(reason: "locationAlreadyAuthorized")
            return
        }
        if isDeniedOrRestricted || !CLLocationManager.locationServicesEnabled() {
            openSystemPrivacySettings()
            return
        }
        promptForAuthorization(reason: "settings", openSettingsIfNoPrompt: true)
    }

    /// 开关 / 引导闸门：弹授权并短暂等待结果；已拒绝则开系统定位页。
    @discardableResult
    func requestAccessAwaitingResult(reason: String) async -> Bool {
        status = manager.authorizationStatus
        if isAuthorized { return true }
        if isDeniedOrRestricted || !CLLocationManager.locationServicesEnabled() {
            openSystemPrivacySettings()
            return false
        }
        promptForAuthorization(reason: reason, openSettingsIfNoPrompt: false)
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            status = manager.authorizationStatus
            if isAuthorized { return true }
            if isDeniedOrRestricted {
                openSystemPrivacySettings()
                return false
            }
        }
        status = manager.authorizationStatus
        return isAuthorized
    }

    /// Wi‑Fi tip 路径：仅在 `notDetermined` 时尝试一次，不强制跳系统设置。
    func ensureAuthorizedIfNeeded(reason: String) {
        status = manager.authorizationStatus
        guard needsRequest else {
            AppLog.debug("NetworkLink", "定位授权无需再请求", [
                "reason": reason,
                "status": Self.describe(status)
            ])
            return
        }
        guard CLLocationManager.locationServicesEnabled() else {
            AppLog.warn("NetworkLink", "系统定位服务关闭，无法读 SSID", ["reason": reason])
            return
        }
        promptForAuthorization(reason: reason, openSettingsIfNoPrompt: false)
    }

    func openSystemPrivacySettings() {
        SystemPrivacyOpener.open(anchor: "Privacy_LocationServices")
    }

    /// 从系统重读授权状态（引导重开后续跑用，不弹窗）。
    func reloadStatusFromSystem(reason: String) {
        status = manager.authorizationStatus
        AppLog.debug("NetworkLink", "已重读定位授权", [
            "reason": reason,
            "status": Self.describe(status)
        ])
    }

    // MARK: - Prompt

    private func promptForAuthorization(reason: String, openSettingsIfNoPrompt: Bool) {
        guard !isPrompting else {
            AppLog.warn("NetworkLink", "定位授权请求进行中，忽略重复点击", ["reason": reason])
            return
        }
        isPrompting = true
        // 设置窗虽已是 regular，仍 activate，否则 LSUIElement 下系统弹窗常不出现。
        NSApp.activate(ignoringOtherApps: true)

        AppLog.warn("NetworkLink", "请求定位授权（仅用于读取 Wi‑Fi 名称）", ["reason": reason])
        // macOS：单靠 requestWhenInUse 经常无弹窗；紧跟 requestLocation 才会真正打断用户。
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()

        guard openSettingsIfNoPrompt else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.isPrompting = false
            }
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.status = self.manager.authorizationStatus
            self.isPrompting = false
            if self.needsRequest {
                AppLog.warn("NetworkLink", "系统未弹出定位授权，改开系统设置", [
                    "status": Self.describe(self.status)
                ])
                self.openSystemPrivacySettings()
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let next = manager.authorizationStatus
            self.status = next
            AppLog.warn("NetworkLink", "定位授权变更", [
                "status": Self.describe(next),
                "services": CLLocationManager.locationServicesEnabled()
            ])
            if self.isAuthorized {
                self.isPrompting = false
                // 已授权后再取一次，促成 CoreWLAN 可读 SSID。
                manager.requestLocation()
                NetworkLinkSession.shared.refresh(reason: "locationAuthorized")
            } else if self.isDeniedOrRestricted {
                self.isPrompting = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            AppLog.warn("NetworkLink", "定位探测成功（不持久化坐标）", [
                "count": locations.count,
                "status": Self.describe(self.status)
            ])
            self.isPrompting = false
            if self.isAuthorized {
                NetworkLinkSession.shared.refresh(reason: "locationFix")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            AppLog.warn("NetworkLink", "定位探测失败", [
                "error": error.localizedDescription,
                "status": Self.describe(self.status)
            ])
            // 未授权时失败属预期；已授权失败仍刷新一次，SSID 不依赖坐标精度。
            self.isPrompting = false
            if self.isAuthorized {
                NetworkLinkSession.shared.refresh(reason: "locationFailButAuthorized")
            }
        }
    }

    static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        case .authorized: return "authorized"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
}
