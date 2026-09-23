import Foundation

public enum TerminalSessionStatus: Equatable, Sendable {
	case launching
	case active
	case waitingForInput
	case failed(String)

	/// Whether a usable terminal still sits behind the session. `.failed` sessions linger in state
	/// after the shell exits but show no status dot and have no attached view, so they read as
	/// "no terminal" to anything filtering on terminal activity.
	public var isLive: Bool {
		switch self {
		case .launching, .active, .waitingForInput:
			true
		case .failed:
			false
		}
	}
}

public struct TerminalSession: Identifiable, Equatable, Sendable {
	public let id: UUID
	public let repositoryPath: String
	public let startingDirectory: String
	/// Typed into the shell once it has started, or `nil` to leave it idle.
	public let startupCommand: String?
	public var tabIndex: Int
	public var status: TerminalSessionStatus

	public init(
		repositoryPath: String,
		startingDirectory: String? = nil,
		startupCommand: String? = nil,
		tabIndex: Int = 1
	) {
		self.id = UUID()
		self.repositoryPath = repositoryPath
		self.startingDirectory = startingDirectory ?? repositoryPath
		let command = startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		self.startupCommand = command.isEmpty ? nil : command
		self.tabIndex = tabIndex
		self.status = .launching
	}
}
