import Foundation

/// Where the pane's screenshot button and screen recordings save, and under what names —
/// Simulator.app's choices, so files from both land together.
enum SimulatorScreenshotFile {
	/// Simulator.app's "Save Screenshots To", then the system screenshot location
	/// (⇧⌘5 ▸ Options), then the Desktop.
	static func folder(
		simulatorLocation: String?,
		systemLocation: String?,
		home: URL = FileManager.default.homeDirectoryForCurrentUser,
		isDirectory: (URL) -> Bool
	) -> URL {
		for location in [simulatorLocation, systemLocation] {
			guard let location, !location.isEmpty else {
				continue
			}
			let url = URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
			if isDirectory(url) {
				return url
			}
		}
		return home.appending(path: "Desktop", directoryHint: .isDirectory)
	}

	/// "Simulator Screenshot - iPhone 17 Pro - 2026-10-07 at 14.03.22.png", as Simulator.app names
	/// them.
	static func name(deviceName: String, date: Date, timeZone: TimeZone = .current) -> String {
		fileName("Simulator Screenshot", deviceName: deviceName, date: date, timeZone: timeZone, extension: "png")
	}

	/// "Simulator Screen Recording - iPhone 17 Pro - 2026-10-07 at 14.03.22.mov", Simulator.app's
	/// name for File ▸ Record Screen.
	static func recordingName(deviceName: String, date: Date, timeZone: TimeZone = .current) -> String {
		fileName("Simulator Screen Recording", deviceName: deviceName, date: date, timeZone: timeZone, extension: "mov")
	}

	private static func fileName(_ prefix: String, deviceName: String, date: Date, timeZone: TimeZone, extension ext: String) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = timeZone
		formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
		let safeName = deviceName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
		return "\(prefix) - \(safeName) - \(formatter.string(from: date)).\(ext)"
	}

	/// A URL in `folder` named `name` that no file has yet: "… 2.png", "… 3.png" when two
	/// screenshots fall in the same second.
	static func unusedURL(in folder: URL, name: String, exists: (URL) -> Bool) -> URL {
		let base = (name as NSString).deletingPathExtension
		let ext = (name as NSString).pathExtension
		var url = folder.appending(path: name, directoryHint: .notDirectory)
		var counter = 2
		while exists(url) {
			url = folder.appending(path: "\(base) \(counter).\(ext)", directoryHint: .notDirectory)
			counter += 1
		}
		return url
	}

	/// Saves the device's screen as a PNG and returns where it went.
	static func save(device: SimulatorDevice, host: SimulatorHost = .shared, date: Date = .now) throws -> URL {
		let data = try host.screenshotPNG(udid: device.id)
		let url = unusedURL(
			in: defaultFolder(),
			name: name(deviceName: device.name, date: date),
			exists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
		)
		try data.write(to: url, options: .withoutOverwriting)
		return url
	}

	/// Where a screenshot or recording goes when nobody said: `folder` with this Mac's settings.
	/// Simulator.app saves its screen recordings to the same place as its screenshots.
	static func defaultFolder() -> URL {
		folder(
			simulatorLocation: UserDefaults(suiteName: "com.apple.iphonesimulator")?.string(forKey: "ScreenShotSaveLocation"),
			systemLocation: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
			isDirectory: isDirectory
		)
	}

	static func isDirectory(_ url: URL) -> Bool {
		var isDirectory: ObjCBool = false
		return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
	}
}
