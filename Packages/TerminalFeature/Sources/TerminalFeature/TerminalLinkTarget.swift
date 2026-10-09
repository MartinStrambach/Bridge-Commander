import Foundation

/// A file a ⌘-clicked link in a pane names, and the line it points at.
public struct TerminalFileLink: Equatable, Sendable {
	/// Absolute and standardized. The file or directory existed when the link was clicked.
	public let path: String
	/// The line of a `path:line` or `path:line:column` link.
	public let line: Int?

	public init(path: String, line: Int?) {
		self.path = path
		self.line = line
	}
}

/// What opening a ⌘-clicked link means.
///
/// SwiftTerm hands over the link's text: an OSC 8 hyperlink's URL, or a URL or path it found in the
/// output by itself. Its own handler checks a path against the app's working directory (`/`), not
/// the shell's, so the relative paths Claude Code prints (`Packages/Foo/Bar.swift:12`) opened
/// nothing; and it reads a bare `Bar.swift:12` as a URL whose scheme is `Bar.swift`. Here a path is
/// tried against the pane's directories first, and only text that names no file is taken as a URL.
public enum TerminalLinkTarget: Equatable, Sendable {
	case file(TerminalFileLink)
	/// Anything but a file — a web page, `mailto:` — for its default handler.
	case url(URL)

	/// - Parameter directories: Where a relative path is looked up, in order.
	/// - Returns: `nil` for a link that names neither an existing file nor a URL.
	public init?(
		link: String,
		relativeTo directories: [String],
		fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
	) {
		let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else {
			return nil
		}

		if let url = URL(string: text), url.isFileURL {
			guard fileExists(url.path) else {
				return nil
			}

			self = .file(TerminalFileLink(path: (url.path as NSString).standardizingPath, line: nil))
			return
		}

		for (path, line) in Self.pathCandidates(text) {
			if let resolved = Self.resolve(path, relativeTo: directories, fileExists: fileExists) {
				self = .file(TerminalFileLink(path: resolved, line: line))
				return
			}
		}

		// `Bar.swift:12` parses as a URL; one whose scheme is followed by nothing but a line and
		// column is a missing file, not something the default handler could open.
		guard
			let url = URL(string: text),
			let scheme = url.scheme,
			text.dropFirst(scheme.count + 1).wholeMatch(of: /\d+(?::\d+)?/) == nil
		else {
			return nil
		}

		self = .url(url)
	}

	/// The text as a path, and the text without a trailing `:line` or `:line:column` (what
	/// compilers and Claude Code put after a path) together with that line. The whole text goes
	/// first, the way SwiftTerm checks it: a file's name may itself end in such digits.
	private static func pathCandidates(_ text: String) -> [(path: String, line: Int?)] {
		var candidates: [(path: String, line: Int?)] = [(text, nil)]
		if
			let match = text.firstMatch(of: /:(\d+)(?::\d+)?$/),
			match.range.lowerBound != text.startIndex
		{
			candidates.append((String(text[..<match.range.lowerBound]), Int(match.1)))
		}
		return candidates
	}

	private static func resolve(
		_ path: String,
		relativeTo directories: [String],
		fileExists: (String) -> Bool
	) -> String? {
		let expanded = (path as NSString).expandingTildeInPath
		let absolutePaths = expanded.hasPrefix("/")
			? [expanded]
			: directories.map { ($0 as NSString).appendingPathComponent(expanded) }
		return absolutePaths
			.map { ($0 as NSString).standardizingPath }
			.first(where: fileExists)
	}
}
