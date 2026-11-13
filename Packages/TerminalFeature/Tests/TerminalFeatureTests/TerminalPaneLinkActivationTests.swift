import AppKit
import Foundation
@testable import SwiftTerm
import Testing

@testable import TerminalFeature

/// A ⌘-click through SwiftTerm's own `activateLink`, the path a real click takes, rather than a
/// direct call to the pane's override. SwiftTerm 1.99.2 checked links there, before any delegate
/// saw them, and blocked every relative path; calling the override directly could not show it.
@MainActor
@Suite("Terminal pane link activation", .serialized)
struct TerminalPaneLinkActivationTests {
	@Test func aClickedRelativePathReachesThePaneWithItsLineAndNoAlert() throws {
		let repository = FileManager.default.temporaryDirectory
			.appending(component: "TerminalPaneLinkActivationTests-\(UUID().uuidString)")
			.resolvingSymlinksInPath()
		try FileManager.default.createDirectory(at: repository.appending(component: "Sources"), withIntermediateDirectories: true)
		try Data().write(to: repository.appending(path: "Sources/Root.swift"))
		defer { try? FileManager.default.removeItem(at: repository) }

		var opened: [TerminalFileLink] = []
		var alerts: [String] = []
		let pane = TerminalPaneView(
			repositoryPath: repository.path,
			sessionId: UUID(),
			events: TerminalPaneEvents(
				onOpenFile: { _, file in
					MainActor.assumeIsolated { opened.append(file) }
				}
			)
		)

		pane.activateLink(
			"Sources/Root.swift:12",
			params: [:],
			isExplicit: false,
			presentAlert: { alert, _, _ in alerts.append(alert.messageText) },
			open: { _ in Issue.record("SwiftTerm opened the file itself") }
		)

		#expect(alerts.isEmpty)
		#expect(opened == [TerminalFileLink(path: repository.appending(path: "Sources/Root.swift").path, line: 12)])
	}
}
