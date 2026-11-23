import XCTest
@testable import Ridge

final class WidgetPermissionGateTests: XCTestCase {
    func test_needs_meetingRequiresCalendar() {
        XCTAssertEqual(WidgetPermissionGate.needs(forWidgetID: "builtin.meeting"), [.calendar])
    }

    func test_needs_captureWidgetsRequireScreenCapture() {
        XCTAssertEqual(WidgetPermissionGate.needs(forWidgetID: "builtin.colorPick"), [.screenCapture])
        XCTAssertEqual(WidgetPermissionGate.needs(forWidgetID: "builtin.ocrSelect"), [.screenCapture])
        XCTAssertEqual(WidgetPermissionGate.needs(forDeckModule: "volume"), [.screenCapture])
        XCTAssertEqual(WidgetPermissionGate.needs(forWidgetID: "system.controlDeck.volume"), [.screenCapture])
    }

    func test_needs_batteryRequiresBluetooth() {
        XCTAssertEqual(WidgetPermissionGate.needs(forDeckModule: "battery"), [.bluetooth])
        XCTAssertEqual(WidgetPermissionGate.needs(forWidgetID: "system.controlDeck.battery"), [.bluetooth])
        XCTAssertEqual(WidgetPermissionGate.needs(forWidgetID: "builtin.peripheralTip"), [.bluetooth])
    }

    func test_needs_networkLinkRequiresLocation() {
        XCTAssertEqual(WidgetPermissionGate.needs(forWidgetID: "builtin.networkLinkTip"), [.location])
    }

    func test_needs_systemFocusRequiresFullDisk() {
        XCTAssertEqual(WidgetPermissionGate.needs(forWidgetID: "builtin.systemFocusTip"), [.fullDiskAccess])
    }

    func test_needs_permissionFreeWidgetsEmpty() {
        XCTAssertTrue(WidgetPermissionGate.needs(forWidgetID: "builtin.media").isEmpty)
        XCTAssertTrue(WidgetPermissionGate.needs(forWidgetID: "builtin.focusTimer").isEmpty)
        XCTAssertTrue(WidgetPermissionGate.needs(forWidgetID: "builtin.copiedNotice").isEmpty)
        XCTAssertTrue(WidgetPermissionGate.needs(forDeckModule: "shelf").isEmpty)
        XCTAssertTrue(WidgetPermissionGate.needs(forDeckModule: "projects").isEmpty)
    }

    func test_defaults_contentWidgetsStartDisabled() {
        let disabled = Set(WidgetSettings.Defaults.disabled)
        XCTAssertTrue(disabled.contains("builtin.meeting"))
        XCTAssertTrue(disabled.contains("builtin.colorPick"))
        XCTAssertTrue(disabled.contains("builtin.networkLinkTip"))
        XCTAssertTrue(disabled.contains("builtin.systemFocusTip"))
        XCTAssertEqual(disabled.count, WidgetLibraryLayout.defaultContentOrder.count)
    }

    func test_onboardingPermissionQueue_dedupesNeedsFromSelectedWidgets() {
        var progress = OnboardingProgress.fresh()
        progress.selectedWidgetIDs = [
            "builtin.meeting",
            "builtin.colorPick",
            "builtin.ocrSelect",
            "builtin.peripheralTip",
            "builtin.networkLinkTip",
            "builtin.systemFocusTip"
        ]
        progress.rebuildPermissionQueue()
        XCTAssertEqual(
            progress.permissionQueue,
            [
                WidgetPermissionGate.Need.calendar.rawValue,
                WidgetPermissionGate.Need.screenCapture.rawValue,
                WidgetPermissionGate.Need.bluetooth.rawValue,
                WidgetPermissionGate.Need.location.rawValue,
                WidgetPermissionGate.Need.fullDiskAccess.rawValue
            ]
        )
    }
}
