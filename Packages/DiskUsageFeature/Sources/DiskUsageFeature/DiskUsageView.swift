import AppKit
import AppUI
import ComposableArchitecture
import QuickLook
import SwiftUI

/// The Disk section: a header with the app's section switcher, then the volume picker, the
/// running scan, or the result — sunburst on the left, the folder's contents on the right.
@ViewAction(for: DiskUsageReducer.self)
public struct DiskUsageView<Header: View>: View {
	@Bindable
	public var store: StoreOf<DiskUsageReducer>
	/// The section switcher, at the start of the header like in every section.
	private let header: Header

	/// Hover is shared by the chart and the list, and never goes through the store: a store
	/// action per mouse move would wake every view bound to it.
	@State
	private var hoveredSegment: SunburstSegment?
	@State
	private var hoveredName: String?
	/// The result takes the keyboard when it appears, and back when it is clicked.
	@FocusState
	private var isResultFocused: Bool
	/// The header's glass capsules morph into one another as the section changes state.
	@Namespace
	private var glassNamespace

	public init(store: StoreOf<DiskUsageReducer>, @ViewBuilder header: () -> Header) {
		self.store = store
		self.header = header()
	}

	public var body: some View {
		content
			// A bar rather than a row above the content: the picker's cards scroll under it with
			// the system's soft edge effect, as content does under a toolbar.
			.safeAreaBar(edge: .top, spacing: 0) {
				headerView
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.onAppear { send(.onAppear) }
		.alert($store.scope(\.$alert, action: \.alert))
	}

	// MARK: - Header

	private var headerView: some View {
		// One container, so the capsules sample the same background and the trailing one morphs
		// between its scanning and result forms instead of one popping out as the other pops in.
		GlassEffectContainer(spacing: 12) {
			HStack(spacing: 12) {
				header
				if store.result != nil {
					HStack(spacing: 2) {
						historyButton(icon: "chevron.left", tooltip: "Back (⌘[)", isEnabled: store.canGoBack) { send(.goBackTapped) }
							.keyboardShortcut("[", modifiers: .command)
						historyButton(icon: "chevron.right", tooltip: "Forward (⌘])", isEnabled: store.canGoForward) { send(.goForwardTapped) }
							.keyboardShortcut("]", modifiers: .command)
					}
					.headerCapsule()
					.glassEffectID("history", in: glassNamespace)
				}
				if !store.path.isEmpty {
					breadcrumb
				}
				Spacer()
				if case let .scanning(_, progress) = store.scan {
					Text("\(progress.scannedBytes.formatted(.byteCount(style: .file))) · \(progress.scannedItems.formatted()) items")
						.scaledFont(.subheadline)
						.foregroundStyle(.secondary)
						.monospacedDigit()
						.contentTransition(.numericText(value: Double(progress.scannedItems)))
						.animation(.default, value: progress.scannedItems)
					HStack(spacing: 2) {
						HeaderButton(icon: "stop.circle.fill", tooltip: "Stop scanning", color: .red) { send(.stopTapped) }
					}
					.headerCapsule()
					.glassEffectID("actions", in: glassNamespace)
				}
				else if store.result != nil {
					HStack(spacing: 2) {
						HeaderButton(
							icon: store.isCurrentFolderStarred ? "star.fill" : "star",
							tooltip: store.isCurrentFolderStarred ? "Remove this folder from the picker's starred folders" : "Star this folder, so the picker offers it",
							color: store.isCurrentFolderStarred ? .yellow : .secondary
						) { send(.starToggled) }
							.symbolEffect(.bounce, value: store.isCurrentFolderStarred)
						HeaderButton(icon: "arrow.clockwise", tooltip: "Scan again (⌘R)", color: .blue) { send(.rescanTapped) }
							.keyboardShortcut("r", modifiers: .command)
						HeaderButton(icon: "internaldrive", tooltip: "Scan another volume or folder") { send(.newScanTapped) }
					}
					.headerCapsule()
					.glassEffectID("actions", in: glassNamespace)
				}
			}
		}
		.animation(.smooth, value: headerPhase)
		.padding()
		.windowTitleBarArea()
	}

	/// What the header shows, for the morph between its forms: the picker, a scan, a result.
	private var headerPhase: Int {
		switch store.scan {
		case .idle: 0
		case .scanning: 1
		case .finished: 2
		}
	}

	private func historyButton(icon: String, tooltip: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
		HeaderButton(icon: icon, tooltip: tooltip, action: action)
			.disabled(!isEnabled)
			.opacity(isEnabled ? 1 : 0.35)
	}

	/// The folders from the scan root to the one on screen; each earlier one is a button back.
	private var breadcrumb: some View {
		ScrollView(.horizontal) {
			HStack(spacing: 4) {
				ForEach(Array(store.path.enumerated()), id: \.element.id) { index, node in
					if index > 0 {
						Image(systemName: "chevron.right")
							.scaledFont(.caption2)
							.foregroundStyle(.tertiary)
					}
					let isLast = index == store.path.count - 1
					Button {
						send(.pathIndexTapped(index))
					} label: {
						Text(index == 0 ? Self.rootTitle(node.name) : node.name)
							.scaledFont(.subheadline)
							.fontWeight(isLast ? .semibold : .regular)
							.foregroundStyle(isLast ? .primary : .secondary)
							.lineLimit(1)
					}
					.buttonStyle(.plain)
					.disabled(isLast)
				}
			}
		}
		.scrollIndicators(.hidden)
		.frame(maxWidth: 600)
	}

	static func rootTitle(_ path: String) -> String {
		path == "/" ? "/" : URL(filePath: path).lastPathComponent
	}

	// MARK: - Content

	@ViewBuilder
	private var content: some View {
		switch store.scan {
		case .idle:
			VolumePickerView(
				volumes: store.volumes,
				lastResult: store.lastResult,
				starredFolders: store.starredFolders,
				onScan: { send(.scanRequested($0)) },
				onChooseFolder: { send(.chooseFolderTapped) },
				onReopen: { send(.lastResultReopened) },
				onUnstar: { send(.starredFolderRemoved($0)) }
			)
		case let .scanning(root, progress):
			scanningView(root: root, progress: progress)
		case let .finished(result):
			if let current = store.currentNode {
				resultView(result: result, current: current)
			}
		}
	}

	private func scanningView(root: URL, progress: DiskScanProgress) -> some View {
		VStack(spacing: 16) {
			Spacer()
			Image(systemName: "internaldrive")
				.scaledFont(size: 36)
				.symbolRenderingMode(.hierarchical)
				.symbolEffect(.breathe)
				.frame(width: 84, height: 84)
				.glassEffect(.regular, in: .circle)
			Text("Scanning \(root.path(percentEncoded: false))")
				.scaledFont(.title3)
				.fontWeight(.semibold)
			VStack(spacing: 4) {
				// The figures roll over as the scan counts up rather than flickering.
				Text("\(progress.scannedBytes.formatted(.byteCount(style: .file))) in \(progress.scannedItems.formatted()) items")
					.monospacedDigit()
					.contentTransition(.numericText(value: Double(progress.scannedItems)))
					.animation(.default, value: progress.scannedItems)
				if let currentPath = progress.currentPath {
					Text(currentPath)
						.lineLimit(1)
						.truncationMode(.middle)
						.foregroundStyle(.secondary)
						.frame(maxWidth: 600)
				}
			}
			.scaledFont(.callout)
			Button("Stop") { send(.stopTapped) }
				.buttonStyle(.scaledGlass)
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}

	private func resultView(result: DiskScanResult, current: DiskNode) -> some View {
		let layout = SunburstLayout(center: current)
		return HStack(alignment: .top, spacing: 16) {
			SunburstChartView(
				layout: layout,
				canGoUp: store.canGoUp,
				hovered: $hoveredSegment,
				selectedNames: store.selectedNames.isEmpty ? Set(hoveredName.map { [$0] } ?? []) : Set(store.selectedNames),
				onOpen: { send(.nodeOpened($0)) },
				onGoUp: { send(.goUpTapped) },
				onSelect: { send(.nodeSelected($0?.name)) },
				onToggle: { send(.selectionToggled($0.name)) }
			)
			.frame(minWidth: 280, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
			.padding(.leading)

			DiskChildrenList(
				node: current,
				layout: layout,
				selectedNames: Set(store.selectedNames),
				leadName: store.selectedName,
				hoveredName: hoveredSegment?.ancestry.first?.name ?? hoveredName,
				deletingNames: store.deletingNames,
				canRemove: { store.state.canRemove($0) },
				onHover: { hoveredName = $0 },
				onSelect: { send(.nodeSelected($0)) },
				onToggle: { send(.selectionToggled($0)) },
				onExtend: { send(.selectionExtended(to: $0)) },
				onOpen: { send(.nodeOpened($0)) },
				onQuickLook: { name in
					send(.nodeSelected(name))
					// An open panel already follows the selection; toggling would close it.
					if !store.isQuickLookShown {
						send(.quickLookToggled)
					}
				},
				onShowInFinder: { name in
					send(.nodeSelected(name))
					send(.showInFinderTapped)
				},
				onMoveToTrash: { name in
					send(.nodeSelected(name))
					send(.moveToTrashTapped)
				},
				onDelete: { name in
					send(.nodeSelected(name))
					send(.deletePermanentlyTapped)
				}
			)
			.frame(minWidth: 320, idealWidth: 420, maxWidth: 520, maxHeight: .infinity)
		}
		// A bar the list scrolls under with the system's soft edge effect; the chart, which does
		// not scroll, stays above it.
		.safeAreaBar(edge: .bottom, spacing: 0) {
			footer(result: result)
		}
		// The mouse's back button goes back, as a browser's does and ⌘[ here.
		.onMouseBackButton {
			send(.goBackTapped)
		}
		.focusable()
		.focusEffectDisabled()
		.focused($isResultFocused)
		.onAppear { isResultFocused = true }
		// Simultaneous, so a click on a row or a segment still does its own thing.
		.simultaneousGesture(TapGesture().onEnded { isResultFocused = true })
		.onKeyPress(keys: DiskKeyboard.keys, phases: [.down, .repeat], action: keyPressed)
		// The folder's items are the panel's collection, so its arrow keys move through them and
		// the selection here follows.
		.quickLookPreview(quickLookItem, in: current.children.filter(\.isOnDisk).compactMap { DiskTree.url(of: store.path + [$0]) })
	}

	// MARK: - Keyboard

	private func keyPressed(_ press: KeyPress) -> KeyPress.Result {
		// A held Space would flick the panel on and off.
		guard press.phase == .down || press.key != .space else { return .handled }
		guard let action = DiskKeyboard.action(for: press.key, modifiers: press.modifiers, hasSelection: store.selectedName != nil) else {
			return .ignored
		}
		send(action)
		return .handled
	}

	// MARK: - Quick Look

	/// What the Quick Look panel shows: the selection while the panel is open. The panel sets it
	/// to the item its arrow keys moved to, and to nil when it closes.
	private var quickLookItem: Binding<URL?> {
		Binding(
			get: { store.isQuickLookShown ? store.selectedURL : nil },
			set: { send(.quickLookItemChanged($0)) }
		)
	}

	/// What is selected and what can be done with it, plus what the scan could not read.
	///
	/// Both states show a two-line title on the left so the footer keeps its height: were the
	/// title to appear only with a selection, the chart above would shrink to make room for it
	/// every time an item is selected and grow back when it is not.
	private func footer(result: DiskScanResult) -> some View {
		// One container, so the buttons sample the same background as they come and go.
		GlassEffectContainer(spacing: 12) {
			HStack(spacing: 12) {
				let selected = store.selectedNodes
				if let node = store.selectedNode {
					if selected.count > 1 {
						footerTitle("\(selected.count.formatted()) items selected", detail: DiskNodeDescription.summary(of: selected, within: store.currentNode))
					}
					else {
						footerTitle(node.name, detail: DiskNodeDescription.summary(of: node, within: store.currentNode))
					}

					Spacer()

					if store.isRemoving {
						ProgressView()
							.controlSize(.small)
						Text(store.deletingNames.count > 1 ? "Removing \(store.deletingNames.count.formatted()) items…" : "Removing…")
							.scaledFont(.caption)
							.foregroundStyle(.secondary)
					}
					else {
						if selected.count == 1 {
							Button {
								send(.showInFinderTapped)
							} label: {
								Label("Show in Finder", systemImage: "folder")
							}
							.buttonStyle(.scaledGlass)
							.disabled(!node.isOnDisk)
						}
						let removable = store.removableSelection
						let protected = selected.filter { store.state.isProtected($0) }
						let removalHelp = removalHelp(removable: removable, protected: protected)
						Button(role: .destructive) {
							send(.moveToTrashTapped)
						} label: {
							Label(removable.count > 1 ? "Move \(removable.count.formatted()) to Trash…" : "Move to Trash…", systemImage: "trash")
						}
						.buttonStyle(.scaledGlass)
						.keyboardShortcut(.delete, modifiers: .command)
						.help(removalHelp ?? "Move to Trash (⌘⌫)")
						.disabled(removable.isEmpty)
						Button(removable.count > 1 ? "Delete \(removable.count.formatted())…" : "Delete…", role: .destructive) {
							send(.deletePermanentlyTapped)
						}
						.buttonStyle(.scaledGlass)
						.keyboardShortcut(.delete, modifiers: [.command, .option])
						.help(removalHelp ?? "Delete Permanently (⌥⌘⌫)")
						.disabled(removable.isEmpty)
					}
				}
				else {
					footerTitle(currentFolderTitle, detail: currentFolderSummary(result: result))
					Spacer()
					if result.inaccessibleFolders > 0 {
						Label(
							"\(result.inaccessibleFolders.formatted()) \(result.inaccessibleFolders == 1 ? "folder" : "folders") could not be read",
							systemImage: "lock"
						)
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
						Button("Grant Full Disk Access…") { send(.openFullDiskAccessSettingsTapped) }
							.buttonStyle(.scaledGlass)
							.controlSize(.small)
					}
				}
			}
		}
		.padding(.horizontal)
		.padding(.vertical, 10)
	}

	/// Why the removal buttons are disabled or act on fewer items than are selected, if they do.
	private func removalHelp(removable: [DiskNode], protected: [DiskNode]) -> String? {
		if !protected.isEmpty {
			let names = protected.map { "“\($0.name)”" }.formatted(.list(type: .and))
			return removable.isEmpty
				? "\(names) cannot be removed: system folders, the home folder, volumes and the scan root are protected"
				: "\(names) will be left alone: system folders, the home folder, volumes and the scan root are protected"
		}
		if removable.isEmpty {
			return "The summed smaller files, hidden space and unreadable folders cannot be removed"
		}
		return nil
	}

	private func footerTitle(_ name: String, detail: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(name)
				.fontWeight(.semibold)
				.lineLimit(1)
				.truncationMode(.middle)
			Text(detail)
				.foregroundStyle(.secondary)
				.monospacedDigit()
				// The figures roll from one selection's to the next.
				.contentTransition(.numericText())
				.animation(.snappy, value: detail)
		}
		.scaledFont(.callout)
	}

	/// The folder on screen: the scan root by its last path component, a subfolder by its name.
	private var currentFolderTitle: String {
		guard let current = store.currentNode else { return "" }
		return store.path.count > 1 ? current.name : Self.rootTitle(current.name)
	}

	/// At the root, how the scan went; in a subfolder, its size and share of its parent.
	private func currentFolderSummary(result: DiskScanResult) -> String {
		guard store.path.count > 1, let current = store.currentNode else { return Self.summary(of: result) }
		return DiskNodeDescription.summary(of: current, within: store.path[store.path.count - 2])
	}

	private static func summary(of result: DiskScanResult) -> String {
		"\(result.root.size.formatted(.byteCount(style: .file))) in \(result.root.itemCount.formatted()) items, scanned in \(result.duration.formatted(.units(allowed: [.minutes, .seconds], width: .narrow)))"
	}

}

/// The map's keys, as in DaisyDisk and Finder: ↑/↓ select (⌥↑/⌥↓, Home/End the first and the
/// last; ⇧↑/⇧↓ extend the selection, ⌘A selects everything), Return, → or ⌘↓ open the selected
/// folder, ← or ⌘↑ go up, Space shows the selection in Quick Look, Escape clears the selection.
/// ⌘[ ⌘] ⌘R ⌘⌫ ⌥⌘⌫ are not here: they are the shortcuts of the buttons that do the same, so they
/// work wherever the focus is.
enum DiskKeyboard {
	static let keys: Set<KeyEquivalent> = [.upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end, .return, .space, .escape, "a"]

	static func action(for key: KeyEquivalent, modifiers: EventModifiers, hasSelection: Bool) -> DiskUsageReducer.Action.View? {
		// Arrow keys carry the numeric-pad flag, so only these count as modifiers.
		let modifiers = modifiers.intersection([.command, .option, .control, .shift])
		switch (key, modifiers) {
		case (.upArrow, []): return .selectionMoved(.previous)
		case (.downArrow, []): return .selectionMoved(.next)
		case (.upArrow, .shift): return .selectionMoved(.previous, extending: true)
		case (.downArrow, .shift): return .selectionMoved(.next, extending: true)
		case ("a", .command): return .selectAllTapped
		case (.home, []), (.upArrow, .option): return .selectionMoved(.first)
		case (.end, []), (.downArrow, .option): return .selectionMoved(.last)
		case (.return, []), (.rightArrow, []), (.downArrow, .command): return .openSelectedTapped
		case (.leftArrow, []), (.upArrow, .command): return .goUpTapped
		case (.space, []) where hasSelection: return .quickLookToggled
		case (.escape, []) where hasSelection: return .nodeSelected(nil)
		default: return nil
		}
	}
}

/// One line about an item for the footer and the list rows' tooltips.
enum DiskNodeDescription {
	static func summary(of node: DiskNode, within parent: DiskNode?) -> String {
		let size = node.size.formatted(.byteCount(style: .file))
		let parentSize = parent?.size ?? 0
		let share = parentSize > 0 ? Double(node.size) / Double(parentSize) : 0
		let shareText = share.formatted(.percent.precision(.fractionLength(1)))
		switch node.kind {
		case .directory where node.isInaccessible:
			return "Could not be read"
		case .directory:
			return "\(size) · \(shareText) · \(node.itemCount.formatted()) items"
		case .file:
			return "\(size) · \(shareText)"
		case let .smallerFiles(count):
			return "\(size) · \(shareText) · \(count.formatted()) files"
		case let .hiddenSpace(purgeable, otherVolumes):
			return "\(size) · \(shareText) · \(Self.hiddenSpaceBreakdown(size: node.size, purgeable: purgeable, otherVolumes: otherVolumes))"
		}
	}

	/// Several items: their total and its share of the folder.
	static func summary(of nodes: [DiskNode], within parent: DiskNode?) -> String {
		let total = nodes.reduce(Int64(0)) { $0 + $1.size }
		let parentSize = parent?.size ?? 0
		let share = parentSize > 0 ? Double(total) / Double(parentSize) : 0
		let items = nodes.reduce(0) { $0 + max(1, $1.itemCount) }
		return "\(total.formatted(.byteCount(style: .file))) · \(share.formatted(.percent.precision(.fractionLength(1)))) · \(items.formatted()) items"
	}

	/// What a volume's hidden space is made of: "4 GB purgeable, 7 GB other volumes, 2 GB other".
	static func hiddenSpaceBreakdown(size: Int64, purgeable: Int64, otherVolumes: Int64) -> String {
		var parts: [String] = []
		if purgeable > 0 {
			parts.append("\(purgeable.formatted(.byteCount(style: .file))) purgeable")
		}
		if otherVolumes > 0 {
			parts.append("\(otherVolumes.formatted(.byteCount(style: .file))) other volumes")
		}
		let rest = size - purgeable - otherVolumes
		if rest > 0 || parts.isEmpty {
			parts.append("\(rest.formatted(.byteCount(style: .file))) unreadable or file system data")
		}
		return parts.joined(separator: ", ")
	}
}

private extension View {
	func headerCapsule() -> some View {
		padding(3)
			.glassEffect(.regular, in: .capsule)
	}
}

// MARK: - Volume picker

/// What to scan: a mounted volume, the home folder, a starred folder, or any folder. Each is a
/// tile that is the control itself: clicking anywhere on it scans (or reopens the last result),
/// and the tile lights under the pointer and sinks while pressed. Solid cards, not glass: a
/// tile is mostly text, and text on glass over the window background was hard to read.
struct VolumePickerView: View {
	let volumes: [DiskVolume]
	/// The result left for the picker, offered for reopening without a scan.
	let lastResult: DiskScanResult?
	/// `DiskLocation` keys, most recently starred last.
	let starredFolders: [String]
	let onScan: (URL) -> Void
	let onChooseFolder: () -> Void
	let onReopen: () -> Void
	let onUnstar: (String) -> Void

	private static let columns = [GridItem(.adaptive(minimum: 340, maximum: 480), spacing: 12, alignment: .top)]

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 28) {
				VStack(alignment: .leading, spacing: 6) {
					Text("Choose what to scan")
						.scaledFont(.title)
						.fontWeight(.bold)
					Text("The scan counts the space every folder takes, as Finder's Get Info does, and shows the result as rings around the folder you are looking at. Nothing is changed until you remove something yourself.")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}

				if let lastResult {
					section("Last scan") {
						PickerTile(
							title: DiskUsageView<EmptyView>.rootTitle(lastResult.root.name),
							subtitle: lastResult.rootURL.path(percentEncoded: false),
							systemImage: "clock.arrow.circlepath",
							actionTitle: "Reopen",
							action: onReopen,
							detail: {
								Text("\(lastResult.root.size.formatted(.byteCount(style: .file))) · scanned \(lastResult.finishedAt.formatted(.relative(presentation: .named)))")
									.scaledFont(.caption)
									.foregroundStyle(.secondary)
									.monospacedDigit()
							}
						)
					}
				}

				section("Volumes and folders") {
					ForEach(volumes) { volume in
						PickerTile(
							title: volume.name,
							subtitle: volume.isStartupVolume ? "Startup volume" : volume.url.path(percentEncoded: false),
							systemImage: volume.isInternal ? "internaldrive" : "externaldrive",
							actionTitle: "Scan",
							action: { onScan(volume.url) },
							detail: {
								Gauge(value: min(1, max(0, volume.usedFraction))) {
									Text("Used")
								}
								.gaugeStyle(.accessoryLinearCapacity)
								.labelsHidden()
								.tint(volume.usedFraction > 0.9 ? Color.red : volume.usedFraction > 0.75 ? Color.orange : Color.accentColor)
								Text("\(volume.usedCapacity.formatted(.byteCount(style: .file))) used of \(volume.totalCapacity.formatted(.byteCount(style: .file)))")
									.scaledFont(.caption)
									.foregroundStyle(.secondary)
									.monospacedDigit()
							}
						)
					}
					PickerTile(
						title: "Home Folder",
						subtitle: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
						systemImage: "house",
						actionTitle: "Scan"
					) {
						onScan(FileManager.default.homeDirectoryForCurrentUser)
					}
					PickerTile(
						title: "Any Folder",
						subtitle: "Pick a folder to scan",
						systemImage: "folder.badge.questionmark",
						actionTitle: "Choose…",
						action: onChooseFolder
					)
				}

				if !starredFolders.isEmpty {
					section("Starred folders") {
						ForEach(starredFolders, id: \.self) { key in
							PickerTile(
								title: DiskLocation.url(forKey: key).lastPathComponent,
								subtitle: key,
								systemImage: "star.fill",
								iconColor: .yellow,
								actionTitle: "Scan",
								action: { onScan(DiskLocation.url(forKey: key)) },
								accessory: {
									Button {
										onUnstar(key)
									} label: {
										Image(systemName: "xmark.circle.fill")
											.symbolRenderingMode(.hierarchical)
											.foregroundStyle(.secondary)
									}
									.buttonStyle(.plain)
									.help("Remove from starred folders")
								}
							)
							.contextMenu {
								Button("Remove from Starred Folders") { onUnstar(key) }
							}
						}
					}
				}
			}
			.frame(maxWidth: 1000, alignment: .leading)
			.frame(maxWidth: .infinity)
			.padding(.horizontal, 24)
			.padding(.vertical, 20)
		}
		.scrollEdgeEffectStyle(.soft, for: .top)
	}

	/// A heading and a grid of tiles.
	private func section(_ title: String, @ViewBuilder tiles: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.scaledFont(.headline)
				.foregroundStyle(.secondary)
			LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 12) {
				tiles()
			}
		}
	}
}

/// One choice in the picker: an icon, then a title, a path and an optional line of detail under
/// them (a volume's capacity, the last scan's age), and the action's name beside a chevron in
/// the bottom corner. An accessory (a starred folder's unstar button) sits at the
/// title's trailing edge; a button there takes its own click, so the tile's action does not run
/// with it. Both are passed by label: a trailing closure binds to the first closure parameter
/// it fits, and a volume's gauge handed over that way ended up as the accessory, beside the
/// title (2026-10-17).
private struct PickerTile<Detail: View, Accessory: View>: View {
	let title: String
	let subtitle: String
	let systemImage: String
	let iconColor: Color
	let actionTitle: String
	let action: () -> Void
	let accessory: Accessory
	let detail: Detail

	@State
	private var isHovered = false

	init(
		title: String,
		subtitle: String,
		systemImage: String,
		iconColor: Color = .accentColor,
		actionTitle: String,
		action: @escaping () -> Void,
		@ViewBuilder detail: () -> Detail = { EmptyView() },
		@ViewBuilder accessory: () -> Accessory = { EmptyView() }
	) {
		self.title = title
		self.subtitle = subtitle
		self.systemImage = systemImage
		self.iconColor = iconColor
		self.actionTitle = actionTitle
		self.action = action
		self.accessory = accessory()
		self.detail = detail()
	}

	var body: some View {
		Button(action: action) {
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .top, spacing: 12) {
					Image(systemName: systemImage)
						.scaledFont(size: 24)
						.symbolRenderingMode(.hierarchical)
						.foregroundStyle(iconColor)
						.frame(width: 34, height: 34)
					VStack(alignment: .leading, spacing: 3) {
						Text(title)
							.scaledFont(.headline)
							.lineLimit(1)
						Text(subtitle)
							.scaledFont(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.truncationMode(.middle)
						detail
							.padding(.top, 4)
					}
					Spacer(minLength: 8)
					accessory
				}
				Spacer(minLength: 0)
				HStack(spacing: 3) {
					Spacer()
					Text(actionTitle)
					Image(systemName: "chevron.right")
						.scaledFont(.caption2)
				}
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
			}
			.padding(16)
			.frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
			.contentShape(.rect(cornerRadius: 16))
		}
		.buttonStyle(TileButtonStyle(isHovered: isHovered))
		.onHover { isHovered = $0 }
		.help(subtitle)
	}
}

/// A tile's surface: a solid card with a hairline border, a little darker under the pointer,
/// darker still and slightly sunk while pressed. The surface is all background, so a button
/// nested in the label still gets its clicks.
private struct TileButtonStyle: ButtonStyle {
	let isHovered: Bool

	func makeBody(configuration: Configuration) -> some View {
		let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
		configuration.label
			.background {
				shape
					.fill(Color(nsColor: .controlBackgroundColor))
					.overlay(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.08 : isHovered ? 0.04 : 0)))
					.overlay(shape.strokeBorder(.separator))
			}
			.scaleEffect(configuration.isPressed ? 0.985 : 1)
			.animation(.easeOut(duration: 0.12), value: configuration.isPressed)
			.animation(.easeOut(duration: 0.12), value: isHovered)
	}
}

// MARK: - Children list

/// The contents of the folder on screen, largest first, each in its chart colour.
struct DiskChildrenList: View {
	let node: DiskNode
	let layout: SunburstLayout
	let selectedNames: Set<String>
	/// The item the arrow keys move from, kept in view.
	let leadName: String?
	let hoveredName: String?
	let deletingNames: Set<String>
	let canRemove: (DiskNode) -> Bool
	let onHover: (String?) -> Void
	/// A plain click: the item alone, or nothing.
	let onSelect: (String?) -> Void
	/// ⌘-click: the item into or out of the selection.
	let onToggle: (String) -> Void
	/// ⇧-click: everything from the anchor to the item.
	let onExtend: (String) -> Void
	let onOpen: (DiskNode) -> Void
	let onQuickLook: (String) -> Void
	let onShowInFinder: (String) -> Void
	let onMoveToTrash: (String) -> Void
	let onDelete: (String) -> Void

	@Environment(\.colorScheme)
	private var colorScheme

	var body: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(spacing: 2) {
					ForEach(node.children) { child in
						row(child)
					}
				}
				.padding(.trailing)
				.padding(.vertical, 4)
			}
			// Keeps a selection made with the arrow keys in view; a clicked row already is.
			.onChange(of: leadName) { _, name in
				guard let name, let child = node.child(named: name) else { return }
				proxy.scrollTo(child.id)
			}
		}
		.onHover { isInside in
			if !isInside { onHover(nil) }
		}
	}

	private func row(_ child: DiskNode) -> some View {
		let isSelected = selectedNames.contains(child.name)
		let isHovered = hoveredName == child.name
		let share = node.size > 0 ? Double(child.size) / Double(node.size) : 0
		return HStack(spacing: 8) {
			RoundedRectangle(cornerRadius: 2)
				.fill(swatchColor(for: child))
				.frame(width: 6, height: 22)
			Image(systemName: icon(for: child))
				.scaledFont(.callout)
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.secondary)
				.frame(width: 18)
			VStack(alignment: .leading, spacing: 3) {
				HStack {
					Text(child.name)
						.scaledFont(.callout)
						.lineLimit(1)
						.truncationMode(.middle)
					Spacer()
					Text(child.isInaccessible ? "—" : child.size.formatted(.byteCount(style: .file)))
						.scaledFont(.callout)
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
				GeometryReader { geometry in
					ZStack(alignment: .leading) {
						Capsule().fill(Color.primary.opacity(0.06))
						Capsule()
							.fill(swatchColor(for: child).opacity(0.8))
							.frame(width: max(2, geometry.size.width * share))
					}
				}
				.frame(height: 4)
			}
			if deletingNames.contains(child.name) {
				ProgressView()
					.controlSize(.mini)
			}
			else if child.isDirectory, !child.isInaccessible {
				Image(systemName: "chevron.right")
					.scaledFont(.caption2)
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.background(
			isSelected
				? Color.accentColor.opacity(0.18)
				: isHovered ? Color.primary.opacity(0.06) : Color.clear,
			in: RoundedRectangle(cornerRadius: 6, style: .continuous)
		)
		.contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
		.onHover { isInside in
			if isInside {
				onHover(child.name)
			}
			else if hoveredName == child.name {
				onHover(nil)
			}
		}
		.onTapGesture(count: 2) {
			onOpen(child)
		}
		.onTapGesture {
			// The modifiers of the click that just ended, as Finder's list reads them.
			let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
			if modifiers.contains(.command) {
				onToggle(child.name)
			}
			else if modifiers.contains(.shift) {
				onExtend(child.name)
			}
			else {
				onSelect(isSelected && selectedNames.count == 1 ? nil : child.name)
			}
		}
		.contextMenu {
			if child.isDirectory, !child.isInaccessible {
				Button("Open") { onOpen(child) }
			}
			if child.isOnDisk {
				Button("Quick Look") { onQuickLook(child.name) }
				Button("Show in Finder") { onShowInFinder(child.name) }
			}
			if canRemove(child) {
				Divider()
				Button("Move to Trash…", role: .destructive) { onMoveToTrash(child.name) }
				Button("Delete Permanently…", role: .destructive) { onDelete(child.name) }
			}
		}
		.help(DiskNodeDescription.summary(of: child, within: node))
	}

	private func icon(for child: DiskNode) -> String {
		switch child.kind {
		case .directory: child.isInaccessible ? "lock.fill" : "folder.fill"
		case .file: "doc"
		case .smallerFiles: "doc.on.doc"
		case .hiddenSpace: "eye.slash"
		}
	}

	/// The colour the chart gives the child; grey for one too small to be drawn.
	private func swatchColor(for child: DiskNode) -> Color {
		guard let segment = layout.segment(forChildNamed: child.name), !child.isInaccessible, child.isOnDisk else {
			return Color.gray.opacity(0.45)
		}
		return Color(
			hue: SunburstLayout.hue(of: segment),
			saturation: child.isDirectory ? 0.62 : 0.4,
			brightness: colorScheme == .dark ? 0.8 : 0.92
		)
	}
}
