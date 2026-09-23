import AppKit
import Testing

@testable import TerminalFeature

@Suite("OptionArrowWordMotion")
struct OptionArrowWordMotionTests {

	private let left = String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)
	private let right = String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)

	/// AppKit flags every arrow key press as a function and numeric-pad key.
	private let arrowFlags: NSEvent.ModifierFlags = [.function, .numericPad]

	private func bytes(
		_ modifiers: NSEvent.ModifierFlags,
		_ key: String,
		optionIsMeta: Bool = false,
		kitty: Bool = false
	) -> [UInt8]? {
		OptionArrowWordMotion.bytes(
			modifiers: modifiers.union(arrowFlags),
			charactersIgnoringModifiers: key,
			optionIsMeta: optionIsMeta,
			kittyProtocolActive: kitty
		)
	}

	@Test("⌥← and ⌥→ send readline's word motion to a legacy shell")
	func legacyWordMotion() {
		#expect(bytes(.option, left) == [0x1B, 0x62])
		#expect(bytes(.option, right) == [0x1B, 0x66])
	}

	@Test("under the kitty protocol they are sent as Alt+arrow")
	func kittyWordMotion() {
		#expect(bytes(.option, left, kitty: true) == Array("\u{1B}[1;3D".utf8))
		#expect(bytes(.option, right, kitty: true) == Array("\u{1B}[1;3C".utf8))
	}

	@Test("a bare arrow is left to SwiftTerm")
	func bareArrow() {
		#expect(bytes([], left) == nil)
	}

	@Test("other modifiers alongside Option are left to SwiftTerm")
	func otherModifiers() {
		#expect(bytes([.option, .shift], left) == nil)
		#expect(bytes([.option, .command], left) == nil)
		#expect(bytes([.option, .control], right) == nil)
	}

	@Test("with Option as Meta SwiftTerm already handles it")
	func optionAsMeta() {
		#expect(bytes(.option, left, optionIsMeta: true) == nil)
	}

	@Test("Option with a character key is left to the compose layer")
	func optionCharacter() {
		#expect(bytes(.option, "4") == nil)
	}
}
