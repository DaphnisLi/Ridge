import XCTest
@testable import Ridge

/// 产品壳层：版本 / 法律资源 / 登录项 API 可调用。
final class AppShellTests: XCTestCase {
    func test_appIdentity_versionAndURLsAreNonEmpty() {
        XCTAssertFalse(AppIdentity.marketingVersion.isEmpty)
        XCTAssertFalse(AppIdentity.buildNumber.isEmpty)
        XCTAssertTrue(AppIdentity.versionLabel.contains(AppIdentity.marketingVersion))
        XCTAssertEqual(AppIdentity.feedbackEmail.contains("@"), true)
        XCTAssertEqual(AppIdentity.appcastURL.scheme, "https")
    }

    func test_legalDocuments_bundledMarkdownResolves() {
        XCTAssertNotNil(
            LegalDocumentOpener.bundledURL(.privacy),
            "隐私政策 md 须打进包或开发态路径可解析"
        )
        XCTAssertNotNil(
            LegalDocumentOpener.bundledURL(.terms),
            "用户协议 md 须打进包或开发态路径可解析"
        )
    }

    @MainActor
    func test_loginItemService_refreshDoesNotCrash() {
        LoginItemService.shared.refresh()
        // 状态随本机登录项变化；仅断言 API 可用。
        _ = LoginItemService.shared.isEnabled
    }

    func test_onboardingCompletedKey_isStable() {
        XCTAssertEqual(AppIdentity.onboardingCompletedKey, "onboarding.completed.v1")
    }
}
