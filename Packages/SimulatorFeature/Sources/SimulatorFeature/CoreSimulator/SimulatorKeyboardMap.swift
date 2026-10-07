import Foundation

/// A key on the simulated keyboard: a USB HID keyboard-page usage, and the modifiers held with it.
public struct SimulatorKeyStroke: Equatable, Sendable {
	public var usage: UInt64
	public var modifiers: [UInt64]

	public init(usage: UInt64, modifiers: [UInt64] = []) {
		self.usage = usage
		self.modifiers = modifiers
	}
}

/// Characters and key names as the HID usages a US keyboard sends for them.
///
/// The guest decodes the usages with its own hardware keyboard layout, which is US unless the
/// simulator was set up otherwise — the same assumption Simulator.app's "Type" pasting makes.
public nonisolated enum SimulatorKeyboardMap {
	static let leftShift: UInt64 = 0xE1
	static let leftControl: UInt64 = 0xE0
	static let leftOption: UInt64 = 0xE2
	static let leftCommand: UInt64 = 0xE3

	/// The keystroke that types `character`, or `nil` when a US keyboard has no key for it.
	public static func keyStroke(for character: Character) -> SimulatorKeyStroke? {
		guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
			// "\r\n" is one Character.
			return character == "\r\n" ? SimulatorKeyStroke(usage: 0x28) : nil
		}

		let value = scalar.value
		switch value {
		case 0x61...0x7A: // a-z
			return SimulatorKeyStroke(usage: 0x04 + UInt64(value - 0x61))
		case 0x41...0x5A: // A-Z
			return SimulatorKeyStroke(usage: 0x04 + UInt64(value - 0x41), modifiers: [leftShift])
		case 0x31...0x39: // 1-9
			return SimulatorKeyStroke(usage: 0x1E + UInt64(value - 0x31))
		case 0x30: // 0
			return SimulatorKeyStroke(usage: 0x27)
		default:
			break
		}

		if let usage = unshifted[character] {
			return SimulatorKeyStroke(usage: usage)
		}
		if let usage = shifted[character] {
			return SimulatorKeyStroke(usage: usage, modifiers: [leftShift])
		}
		return nil
	}

	/// The keystrokes that type `text`, or the characters no key types.
	public static func keyStrokes(for text: String) -> Result<[SimulatorKeyStroke], SimulatorError> {
		var strokes: [SimulatorKeyStroke] = []
		var untypeable: [Character] = []
		for character in text {
			if let stroke = keyStroke(for: character) {
				strokes.append(stroke)
			}
			else if !untypeable.contains(character) {
				untypeable.append(character)
			}
		}
		guard untypeable.isEmpty else {
			return .failure(.untypeableText(untypeable.map { "\"\($0)\"" }.joined(separator: ", ")))
		}
		return .success(strokes)
	}

	/// A named key with optional modifiers, e.g. "return", "cmd+v", "shift+tab", "a".
	public static func keyStroke(named description: String) -> SimulatorKeyStroke? {
		let parts = description
			.lowercased()
			.split(separator: "+", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
		// "cmd++" names the plus key: the last part is empty after a trailing "+".
		guard let last = parts.last else {
			return nil
		}

		let keyName = last.isEmpty && parts.count >= 2 ? "+" : last
		let modifierNames = last.isEmpty ? parts.dropLast(2) : parts.dropLast()
		var modifiers: [UInt64] = []
		for name in modifierNames {
			guard let modifier = modifierUsages[name] else {
				return nil
			}
			modifiers.append(modifier)
		}

		let base: SimulatorKeyStroke? = if let usage = namedKeys[keyName] {
			SimulatorKeyStroke(usage: usage)
		}
		else if keyName.count == 1, let character = keyName.first {
			keyStroke(for: character)
		}
		else {
			nil
		}

		guard var stroke = base else {
			return nil
		}
		for modifier in modifiers where !stroke.modifiers.contains(modifier) {
			stroke.modifiers.append(modifier)
		}
		return stroke
	}

	/// The names `keyStroke(named:)` accepts besides single characters, for the tool description.
	public static let namedKeyList = namedKeys.keys.sorted()

	private static let modifierUsages: [String: UInt64] = [
		"shift": leftShift,
		"ctrl": leftControl,
		"control": leftControl,
		"alt": leftOption,
		"opt": leftOption,
		"option": leftOption,
		"cmd": leftCommand,
		"command": leftCommand,
	]

	private static let namedKeys: [String: UInt64] = [
		"return": 0x28,
		"enter": 0x28,
		"escape": 0x29,
		"esc": 0x29,
		"delete": 0x2A,
		"backspace": 0x2A,
		"tab": 0x2B,
		"space": 0x2C,
		"forwarddelete": 0x4C,
		"right": 0x4F,
		"left": 0x50,
		"down": 0x51,
		"up": 0x52,
		"home": 0x4A,
		"end": 0x4D,
		"pageup": 0x4B,
		"pagedown": 0x4E,
	]

	private static let unshifted: [Character: UInt64] = [
		"\n": 0x28,
		"\r": 0x28,
		"\t": 0x2B,
		" ": 0x2C,
		"-": 0x2D,
		"=": 0x2E,
		"[": 0x2F,
		"]": 0x30,
		"\\": 0x31,
		";": 0x33,
		"'": 0x34,
		"`": 0x35,
		",": 0x36,
		".": 0x37,
		"/": 0x38,
	]

	private static let shifted: [Character: UInt64] = [
		"!": 0x1E,
		"@": 0x1F,
		"#": 0x20,
		"$": 0x21,
		"%": 0x22,
		"^": 0x23,
		"&": 0x24,
		"*": 0x25,
		"(": 0x26,
		")": 0x27,
		"_": 0x2D,
		"+": 0x2E,
		"{": 0x2F,
		"}": 0x30,
		"|": 0x31,
		":": 0x33,
		"\"": 0x34,
		"~": 0x35,
		"<": 0x36,
		">": 0x37,
		"?": 0x38,
	]
}
