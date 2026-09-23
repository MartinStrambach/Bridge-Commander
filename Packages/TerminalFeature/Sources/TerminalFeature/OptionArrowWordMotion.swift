import AppKit

/// What ⌥← and ⌥→ send to the shell: a move by one word, the way Terminal.app and iTerm do it.
///
/// SwiftTerm handles this itself only while Option acts as Meta. The panes run with
/// `optionAsMetaKey` off, so Option stays a compose layer for keyboards that need it (Czech
/// Option+4 = `$`), and in that mode SwiftTerm drops the word motion on both of its keyboard paths:
///
/// - Legacy input (bash, zsh): the key goes through AppKit's key bindings, which turn it into
///   `moveWordLeft:` / `moveWordRight:`. SwiftTerm's `doCommand` has no case for either and logs
///   "Unhandle selector", so nothing reaches the shell.
/// - Kitty keyboard protocol (Claude Code negotiates it): the arrow is encoded as a functional key
///   with Option left out of the modifiers, so the app receives a bare arrow and moves by one
///   character.
///
/// An arrow composes no character on any layout, so taking Option to mean "word" here costs the
/// compose layer nothing.
enum OptionArrowWordMotion {

	/// The bytes to send in place of SwiftTerm's handling, or nil to leave the key to SwiftTerm.
	///
	/// - Parameters:
	///   - modifiers: the event's modifier flags.
	///   - charactersIgnoringModifiers: the event's key, where AppKit reports arrows as
	///     `NSLeftArrowFunctionKey` / `NSRightArrowFunctionKey`.
	///   - optionIsMeta: SwiftTerm's `optionAsMetaKey`; when on, SwiftTerm already sends word motion.
	///   - kittyProtocolActive: whether the running app has pushed kitty keyboard enhancement flags.
	static func bytes(
		modifiers: NSEvent.ModifierFlags,
		charactersIgnoringModifiers: String?,
		optionIsMeta: Bool,
		kittyProtocolActive: Bool
	) -> [UInt8]? {
		let relevant = modifiers.intersection([.option, .command, .control, .shift])
		guard !optionIsMeta, relevant == .option else {
			return nil
		}

		guard let scalar = charactersIgnoringModifiers?.unicodeScalars.first else {
			return nil
		}

		switch Int(scalar.value) {
		case NSLeftArrowFunctionKey:
			// CSI 1;3 D is Alt+Left in the kitty protocol (arrows keep their legacy form, the 3 is
			// 1 + Alt). ESC b is readline's backward-word, what Terminal.app sends for ⌥←.
			return kittyProtocolActive ? Array("\u{1B}[1;3D".utf8) : [0x1B, 0x62]
		case NSRightArrowFunctionKey:
			return kittyProtocolActive ? Array("\u{1B}[1;3C".utf8) : [0x1B, 0x66]
		default:
			return nil
		}
	}
}
