import Foundation

/// The web console's text formats (`console/lib/utils/format.ts`), so a value reads the same in
/// the app as in the browser beside it.
public nonisolated enum HomerFormat {
	/// `07.10.26 18:52:55` — the console's timestamp, in local time.
	public static func timestamp(_ epochSeconds: Double, timeZone: TimeZone = .current) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = timeZone
		formatter.dateFormat = "dd.MM.yy HH:mm:ss"
		return formatter.string(from: Date(timeIntervalSince1970: epochSeconds))
	}

	/// Claude spend in USD. Four decimals: a single run is often well under a cent.
	public static func cost(_ usd: Double) -> String {
		String(format: "$%.4f", usd)
	}

	/// "1h 2m 5s", "2m 5s" or "5s" — how long a command ran (`formatDuration`).
	public static func duration(from start: Double, to end: Double) -> String {
		let seconds = max(0, Int(end) - Int(start))
		let minutes = seconds / 60
		let hours = minutes / 60
		if hours > 0 {
			return "\(hours)h \(minutes % 60)m \(seconds % 60)s"
		}
		if minutes > 0 {
			return "\(minutes)m \(seconds % 60)s"
		}
		return "\(seconds)s"
	}

	/// "in 2d 3h", "in 4h 10m", "in 12m", "in 30s" or "expired" — the Purge column.
	public static func timeUntil(_ epochSeconds: Double, now: Date) -> String {
		let seconds = Int(epochSeconds) - Int(now.timeIntervalSince1970.rounded(.down))
		guard seconds > 0 else {
			return "expired"
		}
		let minutes = seconds / 60
		let hours = minutes / 60
		let days = hours / 24
		if days > 0 {
			return "in \(days)d \(hours % 24)h"
		}
		if hours > 0 {
			return "in \(hours)h \(minutes % 60)m"
		}
		if minutes > 0 {
			return "in \(minutes)m"
		}
		return "in \(seconds)s"
	}
}
