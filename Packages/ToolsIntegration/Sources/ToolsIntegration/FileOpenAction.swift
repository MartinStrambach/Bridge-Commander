import AppKit
import Foundation
import UniformTypeIdentifiers

/// How `FileOpener` opens a file.
///
/// A file goes to its default application, as `open` would hand it on, with two exceptions.
/// Some default applications *run* the file rather than show it: Terminal executes a `.command`
/// or an extensionless executable such as `gradlew`, Python Launcher a `.py`, and an `.app` or
/// `.workflow` launches. Such files go to the source-code editor when they are text, and are shown
/// in Finder otherwise. And a file no application claims (`Package.resolved`, a `.kt` without
/// Android Studio set as its default) goes to the application chosen for its extension in Bridge
/// Commander, which asks for one the first time.
enum FileOpenAction: Equatable {
	/// Opens the file in this application, its default one.
	case open(in: URL)
	/// Opens the file in the application chosen for its type in Bridge Commander.
	case openInChosenApplication
	/// `open -a` with the application registered for source code.
	case openInEditor
	/// `open`: a plain folder shows its contents in Finder.
	case openFolder
	/// `open -R`: selects the file in a Finder window.
	case revealInFinder

	/// What is known about a file when it is clicked.
	struct Facts: Equatable {
		var isDirectory: Bool
		/// Opening it with its default application could run code: an executable, a script, an
		/// application or another kind of active content.
		var isActive: Bool
		/// Its first bytes contain no NUL, so an editor shows it as text.
		var isText: Bool
		var defaultApplication: URL?
	}

	init(_ facts: Facts) {
		if facts.isDirectory {
			// A bundle such as an `.app` is a directory that launches; a plain one opens in Finder.
			self = facts.isActive ? .revealInFinder : .openFolder
		}
		else if facts.isActive {
			self = facts.isText ? .openInEditor : .revealInFinder
		}
		else if let application = facts.defaultApplication {
			self = .open(in: application)
		}
		else {
			self = .openInChosenApplication
		}
	}
}

extension FileOpenAction.Facts {
	/// Extensions whose default handler starts something, after SwiftTerm's link policy (itself
	/// taken from Ghostty's fix for GHSA-cw69-wm67-5pv8).
	private static let activeExtensions: Set = [
		"action", "app", "applescript", "class", "command", "desktop",
		"inetloc", "jar", "mobileconfig", "mpkg", "pkg", "scpt", "terminal",
		"tool", "url", "webloc", "workflow",
	]

	/// Content types whose default handler may run them. Scripts are included because a `.py`
	/// can be bound to Python Launcher.
	private static let activeContentTypes: [UTType] = [.application, .executable, .script]

	/// Reads the facts from the file system and Launch Services.
	init(at path: String) {
		let url = URL(filePath: path)
		let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isExecutableKey, .contentTypeKey])
		let isDirectory = values?.isDirectory ?? false
		let pathExtension = url.pathExtension.lowercased()
		let isActiveType = values?.contentType.map { type in
			Self.activeContentTypes.contains(where: type.conforms(to:))
		} ?? false

		self.init(
			isDirectory: isDirectory,
			isActive: Self.activeExtensions.contains(pathExtension)
				|| isActiveType
				|| (!isDirectory && values?.isExecutable == true),
			isText: !isDirectory && Self.looksLikeText(url),
			defaultApplication: NSWorkspace.shared.urlForApplication(toOpen: url)
		)
	}

	/// Whether the first 8 KB hold no NUL byte. An empty file counts as text.
	static func looksLikeText(_ url: URL) -> Bool {
		guard let handle = try? FileHandle(forReadingFrom: url) else {
			return false
		}
		defer { try? handle.close() }

		guard let data = try? handle.read(upToCount: 8192) else {
			return true
		}
		return !data.contains(0)
	}
}

extension FileOpenAction {
	/// The application `openInEditor` uses: the one registered for source code, or for plain text.
	static func editorApplication() -> URL? {
		NSWorkspace.shared.urlForApplication(toOpen: .sourceCode)
			?? NSWorkspace.shared.urlForApplication(toOpen: .plainText)
	}
}
