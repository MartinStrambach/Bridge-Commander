import Foundation

enum PeriodicRefreshInterval: Int, CaseIterable, Equatable, Sendable {
	case tenSeconds = 10
	case oneMinute = 60
	case threeMinutes = 180
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800

	var displayName: String {
		switch self {
		case .tenSeconds:
			"10 seconds"
		case .oneMinute:
			"1 minute"
		case .threeMinutes:
			"3 minutes"
		case .fiveMinutes:
			"5 minutes"
		case .tenMinutes:
			"10 minutes"
		case .fifteenMinutes:
			"15 minutes"
		case .thirtyMinutes:
			"30 minutes"
		}
	}

	var timeInterval: TimeInterval {
		TimeInterval(rawValue)
	}
}
