import Foundation

public nonisolated extension HomerFormat {
	/// `July 2026` for the ledger's `2026-07` (a UTC month), in the user's language; the raw value
	/// when it is not a `YYYY-MM`.
	static func month(_ month: String, locale: Locale = .current) -> String {
		let utc = TimeZone(identifier: "UTC") ?? .gmt
		let parser = DateFormatter()
		parser.locale = Locale(identifier: "en_US_POSIX")
		parser.timeZone = utc
		parser.dateFormat = "yyyy-MM"
		guard let date = parser.date(from: month) else {
			return month
		}
		let formatter = DateFormatter()
		formatter.locale = locale
		formatter.timeZone = utc
		formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
		return formatter.string(from: date)
	}
}
