import Foundation

public enum XcodeProjectState: Equatable, Sendable {
	case idle
	case checking
	case runningTi
	case runningTg
	case opening
	case error(String)

	public var displayMessage: String {
		switch self {
		case .idle:
			"Open Xcode Project"

		case .checking:
			"Checking"

		case .runningTi:
			"Installing"

		case .runningTg:
			"Generating"

		case .opening:
			"Opening"

		case let .error(message):
			"Error: \(message)"
		}
	}

	public var isProcessing: Bool {
		switch self {
		case .error,
		     .idle:
			false

		default:
			true
		}
	}
}
