import XCTest
@testable import Ridge

/// 岛测试台：DEBUG 策略与播种参数；不测 UI。
final class IslandTestLabTests: XCTestCase {
    #if DEBUG
    func test_tipDurationClamp() {
        XCTAssertEqual(IslandTestLabSettings.clampTipSeconds(0.1), 0.5, accuracy: 0.001)
        XCTAssertEqual(IslandTestLabSettings.clampTipSeconds(3), 3, accuracy: 0.001)
        XCTAssertEqual(IslandTestLabSettings.clampTipSeconds(99), 30, accuracy: 0.001)
    }

    func test_tipDurationOverrideReadsUserDefaults() {
        let enabledKey = "debug.islandTestLab.tipOverrideEnabled"
        let secondsKey = "debug.islandTestLab.tipSeconds"
        let defaults = UserDefaults.standard
        let oldEnabled = defaults.object(forKey: enabledKey)
        let oldSeconds = defaults.object(forKey: secondsKey)
        defer {
            if let oldEnabled {
                defaults.set(oldEnabled, forKey: enabledKey)
            } else {
                defaults.removeObject(forKey: enabledKey)
            }
            if let oldSeconds {
                defaults.set(oldSeconds, forKey: secondsKey)
            } else {
                defaults.removeObject(forKey: secondsKey)
            }
        }

        defaults.set(false, forKey: enabledKey)
        XCTAssertNil(IslandTestLabSettings.resolvedTipDurationNanoseconds())

        defaults.set(true, forKey: enabledKey)
        defaults.set(1.5, forKey: secondsKey)
        XCTAssertEqual(
            IslandTestLabSettings.resolvedTipDurationNanoseconds(),
            UInt64(1.5 * 1_000_000_000)
        )

        let notice = ProjectWatchEndedNotice(
            id: "lab.process.test",
            projectName: "Lab",
            label: "sleep",
            message: "ok",
            endedAt: Date(),
            outcome: .succeeded,
            logPath: nil,
            peakMemoryBytes: 0,
            durationSeconds: 1
        )
        let payload = IslandNoticePayload.processEnded(notice)
        XCTAssertEqual(payload.autoDismissNanoseconds, UInt64(1.5 * 1_000_000_000))
    }

    func test_meetingSeederUrgencyOffsetsMatchLeadRules() {
        let relaxed = IslandTestLabMeetingSeeder.secondsUntilStart(for: .relaxed)
        let warning = IslandTestLabMeetingSeeder.secondsUntilStart(for: .warning)
        let critical = IslandTestLabMeetingSeeder.secondsUntilStart(for: .critical)
        XCTAssertEqual(MeetingLeadUrgency.resolve(secondsToStart: relaxed), .relaxed)
        XCTAssertEqual(MeetingLeadUrgency.resolve(secondsToStart: warning), .warning)
        XCTAssertEqual(MeetingLeadUrgency.resolve(secondsToStart: critical), .critical)
        XCTAssertGreaterThan(relaxed, 5 * 60)
        XCTAssertGreaterThan(warning, 2 * 60)
        XCTAssertLessThanOrEqual(warning, 5 * 60)
        XCTAssertLessThanOrEqual(critical, 2 * 60)
    }

    func test_meetingSeederSampleURLsParse() {
        for platform in MeetingPlatform.supportedForJoin {
            let url = IslandTestLabMeetingSeeder.sampleJoinURL(for: platform)
            XCTAssertFalse(url.absoluteString.isEmpty, platform.rawValue)
        }
    }

    @MainActor
    func test_clearAllTestDataDismissesNoticesAndResetsTipOverride() {
        let center = IslandNoticeCenter.shared
        center.dismiss(id: nil)
        defer { center.dismiss(id: nil) }

        center.present(
            .ramPressure(
                .init(
                    id: "lab.clear.ram",
                    ramUsedBytes: 1,
                    ramPercent: 96,
                    topAppName: "Xcode",
                    topAppMemoryBytes: 1
                )
            )
        )
        XCTAssertNotNil(center.current)

        let defaults = UserDefaults.standard
        let enabledKey = "debug.islandTestLab.tipOverrideEnabled"
        let oldEnabled = defaults.object(forKey: enabledKey)
        defer {
            if let oldEnabled {
                defaults.set(oldEnabled, forKey: enabledKey)
            } else {
                defaults.removeObject(forKey: enabledKey)
            }
        }
        defaults.set(true, forKey: enabledKey)

        IslandTestHarness.shared.clearAllTestData()

        XCTAssertNil(center.current)
        XCTAssertNil(center.slots.secondary)
        XCTAssertFalse(defaults.bool(forKey: enabledKey))
        XCTAssertEqual(IslandTestHarness.shared.statusMessage, L10n.TestLab.statusClearedAll)
    }
    #else
    func test_testLabExcludedFromRelease() {
        XCTAssertTrue(true, "Release 不编译测试台类型")
    }
    #endif
}
