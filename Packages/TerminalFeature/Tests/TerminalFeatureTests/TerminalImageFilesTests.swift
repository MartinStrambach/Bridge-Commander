import AppKit
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

@Suite("Terminal image files")
struct TerminalImageFilesTests {
	@Test func panesReadNoLocalMediaByDefault() {
		let options = TerminalPaneView.startupOptions(readsImageFiles: false)

		#expect(options.kittyGraphics.localMediaPolicy.isEmpty)
		#expect(options.kittyGraphics.storageLimitBytesPerScreen
			== TerminalOptions.default.kittyGraphics.storageLimitBytesPerScreen)
	}

	@Test func readingImageFilesAllowsRegularFilesOnly() {
		let options = TerminalPaneView.startupOptions(readsImageFiles: true)

		#expect(options.kittyGraphics.localMediaPolicy == [.regularFiles])
		#expect(options.kittyGraphics.trustedTemporaryDirectory == nil)
	}

	@Test func otherOptionsStayAtSwiftTermsDefaults() {
		let options = TerminalPaneView.startupOptions(readsImageFiles: true)

		#expect(options.termName == TerminalOptions.default.termName)
		#expect(options.scrollback == TerminalOptions.default.scrollback)
		#expect(options.enableSixelReported == TerminalOptions.default.enableSixelReported)
	}
}

/// The setting reaches the terminal: a program asking whether the terminal reads an image file —
/// the probe Claude Code sends before drawing a picture it names by path — gets `OK` only when
/// it is on.
@MainActor
@Suite("Terminal image file probe", .serialized)
struct TerminalImageFileProbeTests {
	@Test(arguments: [true, false])
	func probeIsAnsweredPerSetting(readsImageFiles: Bool) async throws {
		// A 1×1 RGBA image, as Claude Code's own probe writes.
		let imagePath = FileManager.default.temporaryDirectory
			.appendingPathComponent("bc-image-probe-\(UUID().uuidString).rgba").path
		try Data(count: 4).write(to: URL(fileURLWithPath: imagePath))
		defer { try? FileManager.default.removeItem(atPath: imagePath) }

		// Asks, reads the reply byte by byte without echo, and prints it with its escapes removed.
		let script = #"""
		stty -icanon -echo min 0 time 5
		printf '\033_Gi=31,s=1,v=1,a=q,t=f,f=32;%s\033\\' "$(printf '%s' "$BC_TEST_IMAGE" | base64)"
		reply=$(dd bs=1 count=128 2>/dev/null | tr -d '\033')
		printf 'reply=%s.\n' "$reply"
		exec /bin/cat
		"""#
		let store = TerminalViewStore(
			shellExecutable: "/bin/sh",
			shellArguments: ["-c", script],
			additionalEnvironment: { _ in ["BC_TEST_IMAGE=\(imagePath)"] }
		)
		let session = TerminalSession(repositoryPath: "/")
		let view = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			readsImageFiles: readsImageFiles,
			events: TerminalPaneEvents()
		)
		defer { store.killSession(sessionId: session.id) }

		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(10)
		var screen = ""
		while clock.now < deadline {
			screen = String(decoding: view.getBufferAsData(), as: UTF8.self)
			if screen.contains("reply=") {
				break
			}
			try? await Task.sleep(for: .milliseconds(50))
		}

		#expect(screen.contains("reply=_Gi=31;"))
		#expect(screen.contains("i=31;OK") == readsImageFiles)
	}
}
