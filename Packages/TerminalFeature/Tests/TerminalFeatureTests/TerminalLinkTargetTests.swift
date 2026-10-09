import Foundation
import Testing

@testable import TerminalFeature

@Suite("TerminalLinkTarget")
struct TerminalLinkTargetTests {

	/// The files that exist, for a `fileExists` that never touches the disk.
	private static let files: Set<String> = [
		"/repo/Packages/App/Sources/View.swift",
		"/repo/README.md",
		"/repo/Sources",
		"/shell/cwd/notes.txt",
		"/abs/Thing.swift",
	]

	private func target(_ link: String, in directories: [String] = ["/repo"]) -> TerminalLinkTarget? {
		TerminalLinkTarget(link: link, relativeTo: directories, fileExists: { Self.files.contains($0) })
	}

	@Test("a relative path is found under the pane's directory, not the app's")
	func relativePath() {
		#expect(target("Packages/App/Sources/View.swift") == .file(.init(
			path: "/repo/Packages/App/Sources/View.swift",
			line: nil
		)))
	}

	@Test("a :line suffix is kept as the line, and a :line:column one too")
	func lineSuffix() {
		#expect(target("Packages/App/Sources/View.swift:42") == .file(.init(
			path: "/repo/Packages/App/Sources/View.swift",
			line: 42
		)))
		#expect(target("Packages/App/Sources/View.swift:42:7") == .file(.init(
			path: "/repo/Packages/App/Sources/View.swift",
			line: 42
		)))
	}

	@Test("a bare file name with a line is a file, not a URL whose scheme is its name")
	func bareNameWithLine() {
		#expect(target("README.md:3") == .file(.init(path: "/repo/README.md", line: 3)))
	}

	@Test("directories are tried in order")
	func directoryOrder() {
		#expect(target("notes.txt", in: ["/repo", "/shell/cwd"]) == .file(.init(
			path: "/shell/cwd/notes.txt",
			line: nil
		)))
	}

	@Test("an absolute path is not joined to any directory")
	func absolutePath() {
		#expect(target("/abs/Thing.swift:9") == .file(.init(path: "/abs/Thing.swift", line: 9)))
	}

	@Test("./ and ../ are resolved")
	func dotSegments() {
		#expect(target("./README.md") == .file(.init(path: "/repo/README.md", line: nil)))
		#expect(target("../README.md", in: ["/repo/Sources"]) == .file(.init(
			path: "/repo/README.md",
			line: nil
		)))
	}

	@Test("a file URL is a file")
	func fileURL() {
		#expect(target("file:///abs/Thing.swift") == .file(.init(path: "/abs/Thing.swift", line: nil)))
	}

	@Test("a web URL goes to the default handler")
	func webURL() throws {
		let url = try #require(URL(string: "https://github.com/org/repo/pull/12"))
		#expect(target("https://github.com/org/repo/pull/12") == .url(url))
	}

	@Test("a missing file names nothing, whatever it parses as")
	func missingFile() {
		#expect(target("Missing.swift:12") == nil)
		#expect(target("Missing.swift:12:3") == nil)
		#expect(target("Packages/Missing.swift") == nil)
		#expect(target("file:///nowhere/Thing.swift") == nil)
		#expect(target("   ") == nil)
	}
}
