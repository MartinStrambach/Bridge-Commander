import AppKit
import AppUI
import ComposableArchitecture
import Settings
import SwiftUI
import TerminalFeature

/// How the split's width is shared among its panes.
///
/// The widths are computed, not negotiated, in whole points, the last pane taking what rounding
/// leaves, so the same input always gives the same frames. `HSplitView` was used first and
/// dropped after a report of unequal panes and of a terminal in a pane being resized without
/// end; see the package README for what is and is not known about that.
struct TerminalSplitWidths: Equatable {
	static let dividerWidth: Double = 5
	static let minPaneWidth: Double = 160

	/// Each pane's share of the width left after the dividers; they add up to one.
	private(set) var fractions: [Double]

	/// Equal shares: halves for two panes, thirds for three.
	init(count: Int) {
		fractions = Array(repeating: 1 / Double(max(count, 1)), count: max(count, 1))
	}

	/// The width the panes share out of `total`.
	static func paneSpace(total: Double, count: Int) -> Double {
		max(total - dividerWidth * Double(max(count, 1) - 1), 0)
	}

	func widths(total: Double) -> [Double] {
		let space = Self.paneSpace(total: total, count: fractions.count)
		var widths = fractions.dropLast().map { ($0 * space).rounded() }
		widths.append(max(space - widths.reduce(0, +), 0))
		return widths
	}

	/// The divider after pane `index` dragged `translation` points from where the drag began
	/// (`self` is the shares at that moment), taking from one neighbour what it gives the other
	/// and leaving both at least `minPaneWidth` when there is room for that.
	func draggingDivider(after index: Int, by translation: Double, total: Double) -> Self {
		let space = Self.paneSpace(total: total, count: fractions.count)
		guard fractions.indices.contains(index + 1), space > 0 else {
			return self
		}

		let pair = fractions[index] + fractions[index + 1]
		let minimum = min(Self.minPaneWidth / space, pair / 2)
		var moved = self
		moved.fractions[index] = min(max(fractions[index] + translation / space, minimum), pair - minimum)
		moved.fractions[index + 1] = pair - moved.fractions[index]
		return moved
	}
}

/// The terminals on screen, each under its own tab bar: one, or up to `TerminalTabs.maxPanes`
/// side by side with dividers the user can drag, of one repository or of several.
///
/// One slot per pane, keyed by its position, so the first slot's container — which also keeps
/// every terminal that is off screen — stays mounted whatever the panel shows. The panes get
/// equal widths whenever one is added or removed (`TerminalSplitWidths`).
struct TerminalSplitView: View {
	let store: StoreOf<TerminalLayoutReducer>
	let workspace: StoreOf<TerminalWorkspaceReducer>
	let paneEvents: TerminalPaneEvents

	@Shared(.terminalColorTheme)
	private var terminalColorTheme = TerminalThemeSelection.builtIn(.basicDark)

	@Shared(.terminalProfiles)
	private var terminalProfiles: [TerminalProfile] = []

	@Shared(.terminalCopyOnSelect)
	private var terminalCopyOnSelect = false

	@Shared(.terminalMouseReporting)
	private var terminalMouseReporting = true

	@Shared(.terminalReadsImageFiles)
	private var terminalReadsImageFiles = false

	/// Read here like its sibling settings; the ⌘+/⌘−/⌘0 shortcuts write it through
	/// `TerminalLayoutReducer` so the zoom actions stay testable.
	@Shared(.terminalFontSize)
	private var terminalFontSize = TerminalFontSize.default

	@Shared(.terminalFontName)
	private var terminalFontName = TerminalFontFamily.systemDefault

	/// The two font settings resolved into the one font the panes render with. Resolved here, like
	/// the theme above, so TerminalFeature needs no Settings dependency.
	private var terminalFont: NSFont {
		TerminalFontFamily.resolve(name: terminalFontName, size: terminalFontSize)
	}

	/// The selected theme looked up against the imported profiles.
	private var resolvedTheme: ResolvedTerminalTheme {
		terminalColorTheme.resolve(profiles: terminalProfiles)
	}

	/// The shares the user dragged the dividers to. Used only while it is for the number of panes
	/// on screen: a pane added or removed makes them equal again.
	@State private var draggedWidths: TerminalSplitWidths?
	/// The shares when the current drag began; a drag's translation is measured from its start.
	/// Gesture state, so a drag that is cancelled rather than ended forgets it too.
	@GestureState private var widthsAtDragStart: TerminalSplitWidths?

	var body: some View {
		let panes = workspace.shownSessionIds.compactMap { workspace.sessions[id: $0] }
		let count = max(panes.count, 1)
		return GeometryReader { proxy in
			let shares = draggedWidths.flatMap { $0.fractions.count == count ? $0 : nil }
				?? TerminalSplitWidths(count: count)
			let widths = shares.widths(total: proxy.size.width)
			HStack(spacing: 0) {
				ForEach(0 ..< count, id: \.self) { slot in
					paneView(slot: slot, panes: panes, tabs: workspace.state.tabs(inPane: slot))
						.frame(width: widths[slot])
						.frame(maxHeight: .infinity)
					if slot < count - 1 {
						paneDivider(after: slot, shares: shares, totalWidth: proxy.size.width)
					}
				}
			}
		}
		.onChange(of: count) {
			draggedWidths = nil
		}
	}

	private func paneDivider(after slot: Int, shares: TerminalSplitWidths, totalWidth: Double) -> some View {
		Rectangle()
			.fill(Color(NSColor.windowBackgroundColor))
			.overlay {
				Divider()
			}
			.frame(width: TerminalSplitWidths.dividerWidth)
			.frame(maxHeight: .infinity)
			.contentShape(Rectangle())
			.pointerStyle(.columnResize)
			.gesture(
				DragGesture(minimumDistance: 1, coordinateSpace: .global)
					.updating($widthsAtDragStart) { _, start, _ in
						start = start ?? shares
					}
					.onChanged { drag in
						draggedWidths = (widthsAtDragStart ?? shares).draggingDivider(
							after: slot,
							by: drag.translation.width,
							total: totalWidth
						)
					}
			)
			.help("Drag to resize the panes")
	}

	private func paneView(slot: Int, panes: [TerminalSession], tabs: [TerminalSession]) -> some View {
		let session = panes.indices.contains(slot) ? panes[slot] : nil
		return VStack(spacing: 0) {
			if let session {
				TerminalTabBar(
					store: store,
					workspace: workspace,
					tabs: tabs,
					shownSessionId: session.id,
					paneTitle: panes.count > 1 ? repositoryTitle(for: session) : nil,
					hostsShortcuts: slot == 0
				)
				Divider()
			}

			ZStack {
				TerminalContainerRepresentable(
					terminalViewStore: .shared,
					sessions: workspace.sessions,
					shownSessionIds: panes.map(\.id),
					slot: slot,
					activeSessionId: workspace.activeSessionId,
					colors: TerminalColors(
						foreground: resolvedTheme.foreground,
						background: resolvedTheme.background,
						ansiPalette: resolvedTheme.ansiPalette,
						cursor: resolvedTheme.cursor,
						selection: resolvedTheme.selection
					),
					readsImageFiles: terminalReadsImageFiles,
					copyOnSelect: terminalCopyOnSelect,
					mouseReporting: terminalMouseReporting,
					font: terminalFont,
					events: paneEvents,
					onPaneClicked: { sessionId in
						workspace.send(.paneFocused(sessionId: sessionId))
					}
				)

				if let session, case let .failed(message) = session.status {
					terminalErrorView(message: message, sessionId: session.id)
				}

				if workspace.activeRepositoryPath == nil {
					VStack {
						Spacer()
						Text("Select a repository from the sidebar")
							.scaledFont(.body)
							.foregroundColor(.secondary)
						Spacer()
					}
				}
			}
		}
	}

	/// The folder of the repository a pane shows.
	private func repositoryTitle(for session: TerminalSession) -> String {
		session.repositoryPath == NSHomeDirectory()
			? "~"
			: URL(fileURLWithPath: session.repositoryPath).lastPathComponent
	}

	// MARK: - Error View

	private func terminalErrorView(message: String, sessionId: UUID) -> some View {
		VStack(spacing: 16) {
			Image(systemName: "exclamationmark.triangle.fill")
				.scaledFont(.largeTitle)
				.foregroundColor(.red)
			Text("Terminal failed to start")
				.scaledFont(.headline)
			Text(message)
				.scaledFont(.caption)
				.foregroundColor(.secondary)
			Button("Retry") {
				workspace.send(.retryTab(sessionId: sessionId))
			}
			.buttonStyle(.scaledBorderedProminent)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color(NSColor.textBackgroundColor))
	}
}
