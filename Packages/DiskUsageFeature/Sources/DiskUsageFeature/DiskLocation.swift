import Foundation
import Sharing

/// Locations the Disk section must not remove, as DaisyDisk refuses: the folders macOS is made
/// of, the home folder itself, any volume's root, and the root of the scan. The delete button is
/// permanent, and one careless ⌥⌘⌫ on `/Library` would be the end of the system.
public enum DiskProtectedLocations {
	/// Top-level folders of the system, by their standardized paths.
	static let systemFolders: Set<String> = [
		"/", "/System", "/Library", "/Users", "/Applications", "/private", "/usr", "/bin", "/sbin",
		"/opt", "/Volumes", "/dev", "/etc", "/var", "/tmp", "/cores", "/home", "/Network",
		"/System/Volumes/Data",
	]

	/// Whether `url` is off limits: a system folder, the home folder or its `Library`, a volume
	/// (`volumes`, mounted ones by default), or the root of the scan.
	public static func isProtected(
		_ url: URL,
		scanRoot: URL? = nil,
		volumes: [URL],
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> Bool {
		let key = DiskLocation.key(for: url)
		let homeKey = DiskLocation.key(for: home)
		if systemFolders.contains(key) || key == homeKey || key == homeKey + "/Library" {
			return true
		}
		if let scanRoot, DiskLocation.key(for: scanRoot) == key {
			return true
		}
		return volumes.contains { DiskLocation.key(for: $0) == key }
	}
}

/// Folders pinned to the picker, as standardized paths, most recently starred last.
public nonisolated extension SharedReaderKey where Self == FileStorageKey<[String]>.Default {
	static var diskStarredFolders: Self {
		Self[.fileStorage(applicationSupportURL(name: "diskStarredFolders.json")), default: []]
	}
}

/// One spelling of a location, so paths from scans, the picker, the starred list and the
/// protected list compare: standardized, no trailing slash (but "/").
public enum DiskLocation {
	public static func key(for url: URL) -> String {
		let path = url.standardizedFileURL.path(percentEncoded: false)
		guard path.count > 1, path.hasSuffix("/") else { return path }
		return String(path.dropLast())
	}

	public static func url(forKey key: String) -> URL {
		URL(filePath: key, directoryHint: .isDirectory)
	}
}

private nonisolated func applicationSupportURL(name: String) -> URL {
	let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
	let appSupport = urls.first ?? URL(fileURLWithPath: NSHomeDirectory())
		.appending(component: "Library/Application Support")
	return appSupport
		.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
		.appending(component: name)
}
