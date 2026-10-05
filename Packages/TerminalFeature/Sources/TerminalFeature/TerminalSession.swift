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
	/// The command the settings give this tab, or `nil` to leave it idle. A tab reopened to resume
	/// a Claude conversation types the resume instead (`commandToType`), but keeps this: a retry, or
	/// a later relaunch that finds no Claude running in it, goes by what the tab was opened to run.
	public let startupCommand: String?
	/// The Claude Code conversation this tab picks back up as it opens, if it was reopened at
	/// launch with one running in it.
	public let resumedClaudeSessionId: String?
	/// What the shell is given once it is up: the resume of the conversation the tab had, or else
	/// its startup command.
	public let commandToType: String?
	public var tabIndex: Int
	public var status: TerminalSessionStatus
	/// Set while a tab opened with a startup command has yet to reach its first prompt. That prompt
	/// is the command — Claude, typically — having started, not Claude done with something the user
	/// asked for, so it gets no notification.
	public var awaitsStartupPrompt: Bool

	public init(
		repositoryPath: String,
		startingDirectory: String? = nil,
		startupCommand: String? = nil,
		resumingClaudeSession claudeSessionId: String? = nil,
		tabIndex: Int = 1
	) {
		self.id = UUID()
		self.repositoryPath = repositoryPath
		self.startingDirectory = startingDirectory ?? repositoryPath
		let command = startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		self.startupCommand = command.isEmpty ? nil : command
		let resumeCommand = claudeSessionId.flatMap { ClaudeSession.resumeCommand(sessionId: $0) }
		self.resumedClaudeSessionId = resumeCommand == nil ? nil : claudeSessionId
		self.commandToType = resumeCommand ?? self.startupCommand
		self.tabIndex = tabIndex
		self.status = .launching
		// A resumed Claude booting to its prompt is no more news than a fresh one.
		self.awaitsStartupPrompt = commandToType != nil
	}
}
