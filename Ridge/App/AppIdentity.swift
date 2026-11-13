import Foundation

/// 版本、外链与反馈联系方式（官网 DMG 版）。
enum AppIdentity {
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    static var versionLabel: String {
        "\(marketingVersion) (\(buildNumber))"
    }

    static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
            ?? "Copyright © Daphnis"
    }

    static var bundlePath: String {
        Bundle.main.bundlePath
    }

    /// 反馈邮箱（mailto）。
    static let feedbackEmail = "support@daphnis.app"

    /// 官网 / 发版页（检查更新无 Sparkle 源时回退打开）。
    static let websiteURL = URL(string: "https://daphnis.app/ridge")!
    static let releasesURL = URL(string: "https://daphnis.app/ridge/releases")!

    /// Sparkle appcast；未部署前检查更新会失败并提示，或回退到 releases 页。
    static let appcastURL = URL(string: "https://daphnis.app/ridge/appcast.xml")!

    /// 在线法律文案（可选）；本地 Resources/Legal 优先。
    static let privacyPolicyURL = URL(string: "https://daphnis.app/ridge/privacy")!
    static let termsOfUseURL = URL(string: "https://daphnis.app/ridge/terms")!

    static let onboardingCompletedKey = "onboarding.completed.v1"
    static let autoCheckUpdatesKey = "updates.autoCheck.enabled"
}
