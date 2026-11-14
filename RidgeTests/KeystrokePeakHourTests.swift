import XCTest
@testable import Ridge

/// 峰值时段 = 当天击键次数最多的整点小时。
final class KeystrokePeakHourTests: XCTestCase {
    func test_peakHour_picksMaxCount() {
        let peak = ResourceActivityStore.peakHour(from: [
            14: 10,
            15: 40,
            16: 12
        ])
        XCTAssertEqual(peak?.startHour, 15)
        XCTAssertEqual(peak?.endHour, 16)
    }

    func test_peakHour_firstKeystrokeBecomesPeakImmediately() {
        let peak = ResourceActivityStore.peakHour(from: [14: 1])
        XCTAssertEqual(peak?.startHour, 14)
        XCTAssertEqual(peak?.endHour, 15)
    }

    func test_peakHour_laterHourOvertakes() {
        var hourly = [14: 20]
        XCTAssertEqual(ResourceActivityStore.peakHour(from: hourly)?.startHour, 14)
        hourly[15] = 21
        XCTAssertEqual(ResourceActivityStore.peakHour(from: hourly)?.startHour, 15)
    }

    func test_peakHour_tieBreaksToEarlierHour() {
        let peak = ResourceActivityStore.peakHour(from: [
            10: 5,
            18: 5
        ])
        XCTAssertEqual(peak?.startHour, 10)
        XCTAssertEqual(peak?.endHour, 11)
    }

    func test_peakHour_emptyOrZeroIsNil() {
        XCTAssertNil(ResourceActivityStore.peakHour(from: [:]))
        XCTAssertNil(ResourceActivityStore.peakHour(from: [9: 0]))
    }
}
