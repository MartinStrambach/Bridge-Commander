import AppKit
import Foundation
import UniformTypeIdentifiers

/// Asks which application should open a file no application claims, as Finder does.
@MainActor
enum ApplicationPicker {
	struct Choice {
		var application: URL
		/// Whether every file of this type should open in it from now on.
		var remember: Bool
	}

	/// Shows the panel and waits for it to close; nil when it is cancelled.
	///
	/// Not `runModal`: this is reached from a running effect, and a modal loop entered from a
	/// main-actor job would run other main-actor work inside it.
	static func choose(forFileAt path: String) async -> Choice? {
		let fileType = FileOpenApplications.fileType(ofFileAt: path)
		let fileName = (path as NSString).lastPathComponent

		let panel = NSOpenPanel()
		panel.title = "Choose Application"
		panel.message = "No application is set to open “\(fileName)”. Choose one to open it with."
		panel.prompt = "Open"
		panel.allowedContentTypes = [.application]
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = false
		panel.directoryURL = URL(filePath: "/Applications")

		let remember = NSButton(
			checkboxWithTitle: "Always open \(FileOpenApplications.displayName(ofFileType: fileType)) with this application",
			target: nil,
			action: nil
		)
		remember.state = .on
		panel.accessoryView = remember
		panel.isAccessoryViewDisclosed = true

		NSApp.activate()
		let response = await withCheckedContinuation { continuation in
			panel.begin { continuation.resume(returning: $0) }
		}
		guard response == .OK, let application = panel.url else {
			return nil
		}
		return Choice(application: application, remember: remember.state == .on)
	}
}
