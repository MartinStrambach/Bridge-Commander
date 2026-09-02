/// The reply a terminal sends when focus enters or leaves a pane, once an application has asked for
/// focus reporting with DECSET 1004.
///
/// It matters here because it travels the same path as a keystroke. The app moves focus between
/// panes when the user switches repository, and treating the reply as typing would report both panes
/// the switch touched as having gone back to work.
enum FocusReport {
	private static let focusIn: UInt8 = 0x49 // I
	private static let focusOut: UInt8 = 0x4F // O
	private static let escape: UInt8 = 0x1B
	private static let leftBracket: UInt8 = 0x5B
	private static let eightBitCSI: UInt8 = 0x9B

	/// Whether `data` is exactly a focus report, in either the 7-bit or the 8-bit CSI form a
	/// terminal can emit.
	static func matches(_ data: ArraySlice<UInt8>) -> Bool {
		guard data.last == focusIn || data.last == focusOut else {
			return false
		}

		switch data.count {
		case 2:
			return data.first == eightBitCSI
		case 3:
			return data.first == escape && data.dropFirst().first == leftBracket
		default:
			return false
		}
	}
}
