import Foundation

enum XcodeProjectState: Equatable, Sendable {
	case idle
	case checking
	case runningTi
	case runningTg
	case opening
	case error(String)

	var displayMessage: String {
		switch self {
		case .idle:
			"Open Xcode Project"

		case .checking:
			"Checking"

		case .runningTi:
			"Running ti"

		case .runningTg:
			"Running tg"

		case .opening:
			"Opening"

		case let .error(message):
			"Error: \(message)"
		}
	}

	var isProcessing: Bool {
		switch self {
		case .error,
		     .idle:
			false

		default:
			true
		}
	}
}
