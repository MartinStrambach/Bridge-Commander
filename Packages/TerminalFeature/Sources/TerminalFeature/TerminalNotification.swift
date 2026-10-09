import Foundation

/// A desktop notification a program asked for with an escape sequence, as Ghostty, iTerm2 and
/// WezTerm understand them: OSC 9 (`ESC ] 9 ; body BEL`) and OSC 777
/// (`ESC ] 777 ; notify ; title ; body BEL`). Claude Code sends one of these when it needs
/// permission or has been waiting for input, once its notification channel names such a terminal.
public struct TerminalNotification: Equatable, Sendable {
	/// `nil` for OSC 9, which carries a body only.
	public let title: String?
	public let body: String

	public init(title: String?, body: String) {
		self.title = title
		self.body = body
	}
}

/// What an OSC 9 payload asks for. OSC 9 is shared with ConEmu, whose subcommands put a number
/// first (`9;4;1;50` is a progress report), so a payload like that is not a notification body.
enum OSC9Payload: Equatable {
	case notification(TerminalNotification)
	/// A ConEmu subcommand (SwiftTerm draws the progress bar of `9;4` itself), or nothing to show.
	case ignored

	/// The ConEmu subcommand numbers. Ghostty reads a payload that starts with one of these, then
	/// `;` or the end, as that subcommand rather than as a message.
	private static let conEmuSubcommands = 1...12

	init(_ data: ArraySlice<UInt8>) {
		guard let text = String(bytes: data, encoding: .utf8) else {
			self = .ignored
			return
		}

		let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		if let subcommand = Int(parts[0]), Self.conEmuSubcommands.contains(subcommand) {
			self = .ignored
			return
		}

		self = text.isEmpty ? .ignored : .notification(TerminalNotification(title: nil, body: text))
	}
}

extension TerminalNotification {
	/// Parses an OSC 777 payload. Only `notify` is a notification; the body is everything after
	/// the title, semicolons and all.
	init?(osc777 data: ArraySlice<UInt8>) {
		guard let text = String(bytes: data, encoding: .utf8) else {
			return nil
		}

		let parts = text.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
		guard parts.count == 3, parts[0] == "notify" else {
			return nil
		}

		let title = String(parts[1])
		let body = String(parts[2])
		guard !title.isEmpty || !body.isEmpty else {
			return nil
		}

		self.init(title: title.isEmpty ? nil : title, body: body)
	}
}
