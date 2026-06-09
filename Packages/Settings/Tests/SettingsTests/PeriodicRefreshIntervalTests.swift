import Foundation
import Testing
@testable import Settings

@Suite("PeriodicRefreshInterval")
struct PeriodicRefreshIntervalTests {
	@Test("raw value equals the interval in seconds")
	func rawValuesAreSeconds() {
		#expect(PeriodicRefreshInterval.tenSeconds.rawValue == 10)
		#expect(PeriodicRefreshInterval.oneMinute.rawValue == 60)
		#expect(PeriodicRefreshInterval.threeMinutes.rawValue == 180)
		#expect(PeriodicRefreshInterval.fiveMinutes.rawValue == 300)
		#expect(PeriodicRefreshInterval.tenMinutes.rawValue == 600)
		#expect(PeriodicRefreshInterval.fifteenMinutes.rawValue == 900)
		#expect(PeriodicRefreshInterval.thirtyMinutes.rawValue == 1800)
	}

	@Test("timeInterval mirrors the raw value")
	func timeIntervalMatchesRawValue() {
		for interval in PeriodicRefreshInterval.allCases {
			#expect(interval.timeInterval == TimeInterval(interval.rawValue))
		}
	}

	@Test("displayName is human readable for every case")
	func displayNames() {
		#expect(PeriodicRefreshInterval.tenSeconds.displayName == "10 seconds")
		#expect(PeriodicRefreshInterval.oneMinute.displayName == "1 minute")
		#expect(PeriodicRefreshInterval.threeMinutes.displayName == "3 minutes")
		#expect(PeriodicRefreshInterval.fiveMinutes.displayName == "5 minutes")
		#expect(PeriodicRefreshInterval.tenMinutes.displayName == "10 minutes")
		#expect(PeriodicRefreshInterval.fifteenMinutes.displayName == "15 minutes")
		#expect(PeriodicRefreshInterval.thirtyMinutes.displayName == "30 minutes")
	}

	@Test("every case has a unique, non-empty display name")
	func displayNamesAreUnique() {
		let names = PeriodicRefreshInterval.allCases.map(\.displayName)
		#expect(names.allSatisfy { !$0.isEmpty })
		#expect(Set(names).count == names.count)
	}

	@Test("exposes all seven intervals in ascending order")
	func allCasesOrdered() {
		#expect(PeriodicRefreshInterval.allCases == [
			.tenSeconds, .oneMinute, .threeMinutes, .fiveMinutes,
			.tenMinutes, .fifteenMinutes, .thirtyMinutes,
		])
	}

	@Test("round-trips through its raw value")
	func rawValueRoundTrip() {
		for interval in PeriodicRefreshInterval.allCases {
			#expect(PeriodicRefreshInterval(rawValue: interval.rawValue) == interval)
		}
	}
}
