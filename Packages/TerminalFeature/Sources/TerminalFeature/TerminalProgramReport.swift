import Foundation
import SwiftTerm

/// What the program in a tab says about itself: the root record of the OSC 7501 Program Status
/// Protocol, which SwiftTerm parses and stores for the pane, with its text cleaned up for showing
/// outside the terminal (a notification).
public struct TerminalProgramReport: Equatable, Sendable {
	/// The reported state, in this package's terms so that the app needs no SwiftTerm import.
	public enum State: Equatable, Sendable {
		case working
		/// A dialog is up; what it asks of the user, when the program says.
		case blocked(BlockedOn?)
		case done
		case idle
		case error

		public enum BlockedOn: Equatable, Sendable {
			case permission
			case question
			case signIn
		}
	}

	/// The name the program reports itself under (`app`), such as `claude-code`, or `nil` when it
	/// gave none.
	public let program: String?
	public let state: State
	/// What the program says it is doing, waiting for or finished, if it said anything.
	public let message: String?

	public init(program: String?, state: State, message: String?) {
		self.program = program
		self.state = state
		self.message = message
	}

	/// The pane's root record, or `nil` when it has none.
	///
	/// Programs report their session on the root record (no `id`), and may put each subtask on a
	/// record of its own — Claude Code does for its subagents and background tasks. Only the root
	/// says whether the program is waiting for the user: a task still running after Claude's turn
	/// ended leaves the root `done`.
	init?(records: [TerminalProgramStatus]) {
		guard let root = records.first(where: { $0.id.isEmpty }) else {
			return nil
		}

		self.init(
			program: Self.displayText(root.effectiveApp),
			state: State(root.state, kind: root.kind),
			// Per field, so a message that cleans up to nothing still leaves the title.
			message: Self.displayText(root.message, maxLength: Self.maxMessageLength)
				?? Self.displayText(root.title, maxLength: Self.maxMessageLength)
		)
	}

	/// The program's name as a notification shows it.
	public var displayName: String {
		switch program {
		case "claude-code":
			"Claude"
		case let program?:
			program
		case nil:
			"A program"
		}
	}

	/// What a notification says about the program: the state in words of the app's own, then the
	/// program's message, which the protocol says to show without reading meaning into it.
	public var notificationBody: String {
		let sentence = switch state {
		case .working:
			"\(displayName) is working"
		case .blocked(.permission):
			"\(displayName) needs your permission"
		case .blocked(.question):
			"\(displayName) has a question"
		case .blocked(.signIn):
			"\(displayName) needs you to sign in"
		case .blocked(nil):
			"\(displayName) needs your input"
		case .done:
			"\(displayName) is done"
		case .idle:
			"\(displayName) is waiting for your input"
		case .error:
			"\(displayName) ran into an error"
		}
		return message.map { "\(sentence): \($0)" } ?? "\(sentence)."
	}

	/// Longest message kept, in characters. A report may carry a couple of kilobytes; a
	/// notification shows a line or two of it.
	private static let maxMessageLength = 300

	/// The text of a report as it can be shown outside the terminal grid, or `nil` when nothing is
	/// left. SwiftTerm has already refused control characters; the protocol leaves the rest to the
	/// host: invisible formatting characters (text direction overrides among them) could make a
	/// notification read differently from what was sent, so they are dropped.
	static func displayText(_ text: String?, maxLength: Int = .max) -> String? {
		guard let text else {
			return nil
		}

		var scalars = String.UnicodeScalarView()
		for scalar in text.unicodeScalars {
			switch scalar.properties.generalCategory {
			case .format,
			     .control:
				continue
			case .lineSeparator,
			     .paragraphSeparator:
				scalars.append(" ")
			default:
				scalars.append(scalar)
			}
		}
		let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleaned.isEmpty else {
			return nil
		}

		return cleaned.count > maxLength ? String(cleaned.prefix(maxLength - 1)) + "…" : cleaned
	}
}

extension TerminalProgramReport.State {
	init(_ state: TerminalProgramStatusState, kind: TerminalProgramStatusKind?) {
		switch state {
		case .working:
			self = .working
		case .blocked:
			self = .blocked(kind.map {
				switch $0 {
				case .permission:
					.permission
				case .question:
					.question
				case .auth:
					.signIn
				}
			})
		case .done:
			self = .done
		case .idle:
			self = .idle
		case .error:
			self = .error
		}
	}
}
