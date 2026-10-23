import AppKit
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

/// Collects the files a pane asked to open, in order.
@MainActor
private final class OpenedFiles {
	var items: [TerminalFileLink] = []
}

/// The pane end of ⌘-clicked links: which directories a relative path is looked up in, and in what
/// order. What counts as a path or a URL is `TerminalLinkTargetTests`.
@MainActor
@Suite("Terminal pane links", .serialized)
struct TerminalPaneLinkTests {
	/// A repository with `Shared.swift` at its root and in `Sub/`, and `Root.swift` at its root only.
	private func makeRepository() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appending(component: "TerminalPaneLinkTests-\(UUID().uuidString)")
			.resolvingSymlinksInPath()
		try FileManager.default.createDirectory(at: root.appending(component: "Sub"), withIntermediateDirectories: true)
		for path in ["Shared.swift", "Sub/Shared.swift", "Root.swift"] {
			try Data().write(to: root.appending(path: path))
		}
		return root
	}

	private func resolved(_ path: String) -> String {
		URL(fileURLWithPath: path).resolvingSymlinksInPath().path
	}

	@Test func aRelativePathIsLookedUpAtTheRepositoryRootWithItsLine() throws {
		let repository = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repository) }
		let opened = OpenedFiles()
		let sessionId = UUID()
		let pane = TerminalPaneView(
			repositoryPath: repository.path,
			sessionId: sessionId,
			events: TerminalPaneEvents(
				onOpenFile: { id, file in
					MainActor.assumeIsolated {
						#expect(id == sessionId)
						opened.items.append(file)
					}
				}
			)
		)

		pane.requestOpenLink(source: pane, link: "Root.swift:12", params: [:])

		#expect(opened.items.map { resolved($0.path) } == [repository.appending(component: "Root.swift").path])
		#expect(opened.items.map(\.line) == [12])
	}

	/// The program that printed the path was started where the shell is now, so that directory
	/// wins over the repository root; a file only at the root is still found.
	@Test func theShellsDirectoryComesBeforeTheRepositoryRoot() async throws {
		let repository = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repository) }
		let opened = OpenedFiles()
		let store = TerminalViewStore(shellExecutable: "/bin/cat", shellArguments: [])
		let session = TerminalSession(
			repositoryPath: repository.path,
			startingDirectory: repository.appending(component: "Sub").path
		)
		let pane = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents(
				onOpenFile: { _, file in
					MainActor.assumeIsolated { opened.items.append(file) }
				}
			)
		)
		defer { store.killSession(sessionId: session.id) }
		// The child chdirs after the fork; until then it is still in this process's directory.
		let sub = repository.appending(component: "Sub").path
		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(5)
		while pane.currentDirectory.map(resolved) != sub, clock.now < deadline {
			try await Task.sleep(for: .milliseconds(20))
		}
		try #require(pane.currentDirectory.map(resolved) == sub)

		pane.requestOpenLink(source: pane, link: "Shared.swift", params: [:])
		pane.requestOpenLink(source: pane, link: "Root.swift", params: [:])

		#expect(opened.items.map { resolved($0.path) } == [
			repository.appending(path: "Sub/Shared.swift").path,
			repository.appending(component: "Root.swift").path,
		])
	}
}

@Suite("Dropped path escaping")
struct DroppedPathEscapingTests {
	@Test func plainPathsAreLeftAlone() {
		#expect("/Users/me/Project-1/file_name.v2,final=@+:x".shellEscaped == "/Users/me/Project-1/file_name.v2,final=@+:x")
	}

	@Test func shellSpecialCharactersAreBackslashed() {
		#expect("/foo bar".shellEscaped == #"/foo\ bar"#)
		#expect("/it's".shellEscaped == #"/it\'s"#)
		#expect(#"/a"b$c;d&e|f(g)*?~`h"#.shellEscaped == #"/a\"b\$c\;d\&e\|f\(g\)\*\?\~\`h"#)
	}

	/// Letters outside ASCII are letters, not something the shell interprets.
	@Test func nonASCIILettersAreLeftAlone() {
		#expect("/Dokumenty/Příliš žluťoučký".shellEscaped == #"/Dokumenty/Příliš\ žluťoučký"#)
	}
}
