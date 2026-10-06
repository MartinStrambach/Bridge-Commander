import Combine
import Sparkle
import SwiftUI

/// Whether this build starts Sparkle's updater. Only Release builds do: a Debug build runs out
/// of DerivedData, where installing an update would replace the build being worked on with the
/// published app.
let startsUpdater: Bool = {
	#if DEBUG
		false
	#else
		true
	#endif
}()

/// Mirrors the `SPUUpdater` properties the update UI shows. They are KVO compliant, so a change
/// made anywhere — Sparkle's own permission prompt, the update dialog's checkbox, Settings —
/// shows up in every view. `canCheckForUpdates` is false while a check is already running, and
/// stays false in a build whose updater never started.
@MainActor
final class UpdaterViewModel: ObservableObject {
	@Published
	private(set) var canCheckForUpdates = false

	@Published
	private(set) var automaticallyChecksForUpdates = false

	@Published
	private(set) var automaticallyDownloadsUpdates = false

	/// False while automatic checks are off: Sparkle only installs on its own after a scheduled
	/// check, so the download option means nothing without them.
	@Published
	private(set) var allowsAutomaticUpdates = false

	/// Not KVO compliant, so it is re-read whenever a check finishes (`canCheckForUpdates`
	/// turning true again).
	@Published
	private(set) var lastUpdateCheckDate: Date?

	let updater: SPUUpdater

	init(updater: SPUUpdater) {
		self.updater = updater
		updater.publisher(for: \.canCheckForUpdates)
			.assign(to: &$canCheckForUpdates)
		updater.publisher(for: \.automaticallyChecksForUpdates)
			.assign(to: &$automaticallyChecksForUpdates)
		updater.publisher(for: \.automaticallyDownloadsUpdates)
			.assign(to: &$automaticallyDownloadsUpdates)
		updater.publisher(for: \.allowsAutomaticUpdates)
			.assign(to: &$allowsAutomaticUpdates)
		updater.publisher(for: \.canCheckForUpdates)
			.map { [updater] _ in updater.lastUpdateCheckDate }
			.assign(to: &$lastUpdateCheckDate)
	}

	/// Written straight to the updater, which persists them in user defaults itself; the
	/// published copies follow through KVO.
	func setAutomaticallyChecksForUpdates(_ isOn: Bool) {
		updater.automaticallyChecksForUpdates = isOn
	}

	func setAutomaticallyDownloadsUpdates(_ isOn: Bool) {
		updater.automaticallyDownloadsUpdates = isOn
	}

	func checkForUpdates() {
		updater.checkForUpdates()
	}
}

/// The "Check for Updates…" item in the app menu. Sparkle checks on its own schedule once the
/// user has allowed it (it asks on the second launch, or Settings ▸ Updates); this is the
/// manual check.
struct CheckForUpdatesView: View {
	@StateObject
	private var viewModel: UpdaterViewModel

	init(updater: SPUUpdater) {
		_viewModel = StateObject(wrappedValue: UpdaterViewModel(updater: updater))
	}

	var body: some View {
		Button("Check for Updates…") {
			viewModel.checkForUpdates()
		}
		.disabled(!viewModel.canCheckForUpdates)
	}
}
