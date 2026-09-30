/// A reply the terminal writes to the child on its own: a focus report, or the answer to a query the
/// program in the pane sent.
///
/// It matters here because it travels the same path as a keystroke. The app moves focus between
/// panes when the user switches tab or repository, and Claude Code answers each focus change by
/// asking for the cell size (`CSI 16 t`), so treating either reply as typing reported both panes the
/// switch touched as having gone back to work — and the one left behind, off screen by then, posted
/// a fresh "waiting" notification when it settled back at its prompt 1.5 s later.
///
/// Only shapes no key, mouse event or paste produces are recognised. The cursor-position report
/// (`CSI row;col R`) is deliberately left out: it has the same shape as F3 with a modifier.
enum TerminalReply {
	private static let escape: UInt8 = 0x1B
	private static let bell: UInt8 = 0x07
	private static let backslash: UInt8 = 0x5C
	private static let leftBracket: UInt8 = 0x5B
	private static let rightBracket: UInt8 = 0x5D // OSC
	private static let upperP: UInt8 = 0x50 // DCS
	private static let eightBitCSI: UInt8 = 0x9B

	private static let question: UInt8 = 0x3F
	private static let greaterThan: UInt8 = 0x3E
	private static let dollar: UInt8 = 0x24

	private static let focusIn: UInt8 = 0x49 // I
	private static let focusOut: UInt8 = 0x4F // O
	private static let windowReport: UInt8 = 0x74 // t
	private static let deviceAttributes: UInt8 = 0x63 // c
	private static let statusReport: UInt8 = 0x6E // n
	private static let modeReport: UInt8 = 0x79 // y
	private static let keyboardFlags: UInt8 = 0x75 // u

	/// Whether `data` is exactly one terminal reply, in the 7-bit form, or for control sequences
	/// also the 8-bit CSI form a terminal can emit.
	static func matches(_ data: ArraySlice<UInt8>) -> Bool {
		let bytes = Array(data)
		guard let first = bytes.first else {
			return false
		}

		if first == eightBitCSI {
			return isControlSequenceReply(bytes.dropFirst())
		}

		guard first == escape, bytes.count >= 2 else {
			return false
		}

		switch bytes[1] {
		case leftBracket:
			return isControlSequenceReply(bytes.dropFirst(2))
		case rightBracket,
		     upperP:
			return isStringReply(bytes.dropFirst(2))
		default:
			return false
		}
	}

	/// `rest` is everything after the CSI introducer: parameters, then one final byte.
	private static func isControlSequenceReply(_ rest: ArraySlice<UInt8>) -> Bool {
		guard let final = rest.last else {
			return false
		}

		var body = rest.dropLast()
		var prefix: UInt8?
		if let lead = body.first, lead == question || lead == greaterThan {
			prefix = lead
			body = body.dropFirst()
		}

		switch final {
		case focusIn,
		     focusOut:
			return prefix == nil && body.isEmpty

		case windowReport:
			// XTWINOPS: `4;h;w t` window size, `6;h;w t` cell size, `8;rows;cols t` text area.
			return prefix == nil && isParameters(body)

		case deviceAttributes:
			// DA1 `?…c`, DA2 `>…c`.
			return prefix != nil && isParameters(body)

		case statusReport:
			// DSR `0 n`, and the color-scheme report `?997;1 n`.
			return prefix != greaterThan && isParameters(body)

		case modeReport:
			// DECRPM `?mode;value$y` and its ANSI form `mode;value$y`.
			guard prefix != greaterThan, body.last == dollar else {
				return false
			}
			return isParameters(body.dropLast())

		case keyboardFlags:
			// The kitty keyboard protocol's `?flags u`. Key events end in `u` too, but never with `?`.
			return prefix == question && isParameters(body)

		default:
			return false
		}
	}

	/// OSC and DCS replies (a color query's `rgb:…`, XTVERSION): a payload closed by BEL or ST.
	/// Requiring the terminator keeps Option+] and Option+⇧P, which send the bare introducer, out.
	private static func isStringReply(_ rest: ArraySlice<UInt8>) -> Bool {
		if rest.last == bell {
			return rest.count > 1
		}

		return rest.count > 2 && rest.suffix(2).elementsEqual([escape, backslash])
	}

	private static func isParameters(_ body: ArraySlice<UInt8>) -> Bool {
		!body.isEmpty && body.allSatisfy { (0x30 ... 0x39).contains($0) || $0 == 0x3B }
	}
}
