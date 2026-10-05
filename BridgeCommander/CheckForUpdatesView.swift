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

/// Mirrors `SPUUpdater.canCheckForUpdates`, which is false while a check is already running,
/// and stays false in a build whose updater never started.
@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
	@Published
	var canCheckForUpdates = false

	init(updater: SPUUpdater) {
		updater.publisher(for: \.canCheckForUpdates)
			.assign(to: &$canCheckForUpdates)
	}
}

/// The "Check for Updates…" item in the app menu. Sparkle checks on its own schedule once the
/// user has allowed it (it asks on the second launch); this is the manual check.
struct CheckForUpdatesView: View {
	@StateObject
	private var viewModel: CheckForUpdatesViewModel

	private let updater: SPUUpdater

	init(updater: SPUUpdater) {
		self.updater = updater
		_viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
	}

	var body: some View {
		Button("Check for Updates…") {
			updater.checkForUpdates()
		}
		.disabled(!viewModel.canCheckForUpdates)
	}
}
