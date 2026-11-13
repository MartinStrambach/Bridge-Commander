import AppKit
import Foundation

/// The applications chosen in Bridge Commander for files no application claims, by file type.
///
/// Kept here rather than made the system default: choosing one must not change what Finder does
/// with the file. Settings ▸ External Apps lists them for changing or removing.
public struct FileOpenApplications: Equatable, Sendable {
	/// Bundle identifiers by file type: a lowercased extension, or `""` for files without one.
	/// A bundle identifier rather than a path, so the choice survives the application being
	/// moved or renamed (`Xcode-27.2.0.app`).
	public var bundleIdentifiers: [String: String]

	public init(bundleIdentifiers: [String: String] = [:]) {
		self.bundleIdentifiers = bundleIdentifiers
	}

	/// The file type a choice is stored under: the lowercased extension, `""` when there is none.
	public static func fileType(ofFileAt path: String) -> String {
		(path as NSString).pathExtension.lowercased()
	}

	/// How a file type is named in the picker and in Settings.
	public static func displayName(ofFileType fileType: String) -> String {
		fileType.isEmpty ? "files without an extension" : ".\(fileType) files"
	}

	/// The installed application chosen for the type, or nil when none is chosen or it is gone.
	public func application(forFileType fileType: String) -> URL? {
		bundleIdentifiers[fileType].flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
	}

	/// The identifier a choice of this application is stored as, nil for a bundle without one.
	public static func bundleIdentifier(ofApplicationAt url: URL) -> String? {
		Bundle(url: url)?.bundleIdentifier
	}
}

extension FileOpenApplications: RawRepresentable {
	public init?(rawValue: String) {
		guard let bundleIdentifiers = try? JSONDecoder().decode([String: String].self, from: Data(rawValue.utf8)) else {
			return nil
		}
		self.init(bundleIdentifiers: bundleIdentifiers)
	}

	public var rawValue: String {
		let encoder = JSONEncoder()
		// Stable output, so an unchanged value is never written back as a "new" one.
		encoder.outputFormatting = .sortedKeys
		// The dictionary, and the type is not `Codable`: a type both `RawRepresentable` and `Codable`
		// encodes as its `rawValue`, which would encode the type again, without end.
		guard let data = try? encoder.encode(bundleIdentifiers) else {
			return ""
		}
		return String(decoding: data, as: UTF8.self)
	}

	/// Spelled out: as a `RawRepresentable` the type would otherwise pick up the standard
	/// library's `==` that compares raw values, i.e. JSON strings.
	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.bundleIdentifiers == rhs.bundleIdentifiers
	}
}
