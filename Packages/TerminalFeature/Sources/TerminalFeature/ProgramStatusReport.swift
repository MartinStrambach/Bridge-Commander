import Foundation
import SwiftTerm

/// What the program in a tab said about itself when it began waiting, cleaned up for showing
/// outside the terminal (a notification).
public struct TerminalProgramReport: Equatable, Sendable {
	/// The name the program reports itself under (`app`), such as `claude-code`, or `nil` when it
	/// gave none.
	public let program: String?
	/// What the program says it is waiting for, or what it finished, if it said anything.
	public let message: String?

	public init(program: String?, message: String?) {
		self.program = program
		self.message = message
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

	/// Longest message kept, in characters. A report may carry a couple of kilobytes; a
	/// notification shows a line or two of it.
	fileprivate static let maxMessageLength = 300

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

/// A program's own word on what it is doing: the root record of the OSC 7501 Program Status
/// Protocol, which SwiftTerm parses and stores for the pane.
struct ProgramStatusReport: Equatable {
	let state: TerminalProgramStatusState
	let report: TerminalProgramReport

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

		state = root.state
		report = TerminalProgramReport(
			program: TerminalProgramReport.displayText(root.effectiveApp),
			message: TerminalProgramReport.displayText(
				root.message ?? root.title,
				maxLength: TerminalProgramReport.maxMessageLength
			)
		)
	}

	init(state: TerminalProgramStatusState, report: TerminalProgramReport) {
		self.state = state
		self.report = report
	}
}
