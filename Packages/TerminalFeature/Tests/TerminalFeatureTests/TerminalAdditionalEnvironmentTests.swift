import AppKit
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

/// The store's `additionalEnvironment` reaches the pane's shell, keyed by the pane's own session.
@MainActor
@Suite("Terminal additional environment", .serialized)
struct TerminalAdditionalEnvironmentTests {
	private let processDelegate = TerminalProcessDelegate(onFailed: { _ in })

	@Test("the shell starts with the variables given for its session")
	func shellSeesSessionVariables() async {
		let store = TerminalViewStore(
			shellExecutable: "/bin/sh",
			shellArguments: ["-c", #"printf 'id=%s url=%s\n' "$BC_TEST_SESSION" "$BC_TEST_URL"; exec /bin/cat"#],
			additionalEnvironment: { session in
				["BC_TEST_SESSION=\(session.id.uuidString)", "BC_TEST_URL=http://127.0.0.1:1/mcp"]
			}
		)
		let session = TerminalSession(repositoryPath: "/")
		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: processDelegate,
			onStatusChange: { _, _ in },
			onNotification: { _, _ in }
		)
		defer { store.killSession(sessionId: session.id) }

		let expected = "id=\(session.id.uuidString) url=http://127.0.0.1:1/mcp"
		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(5)
		var screen = ""
		while clock.now < deadline {
			screen = String(decoding: view.getBufferAsData(), as: UTF8.self)
			if screen.contains(expected) {
				break
			}
			try? await Task.sleep(for: .milliseconds(50))
		}
		#expect(screen.contains(expected))
	}
}
