import AppUI
import ComposableArchitecture
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

	public init(store: StoreOf<DiskUsageReducer>, @ViewBuilder header: () -> Header) {
		self.store = store
		self.header = header()
	}

	public var body: some View {
		VStack(spacing: 0) {
			headerView
			content
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.onAppear { send(.onAppear) }
		.alert($store.scope(\.$alert, action: \.alert))
	}

	// MARK: - Header

	private var headerView: some View {
		HStack(spacing: 12) {
			header
			if !store.path.isEmpty {
				breadcrumb
			}
			Spacer()
			if case let .scanning(_, progress) = store.scan {
				Text("\(progress.scannedBytes.formatted(.byteCount(style: .file))) · \(progress.scannedItems.formatted()) items")
					.scaledFont(.subheadline)
					.foregroundStyle(.secondary)
					.monospacedDigit()
				HStack(spacing: 2) {
					HeaderButton(icon: "stop.circle.fill", tooltip: "Stop scanning", color: .red) { send(.stopTapped) }
				}
				.headerCapsule()
			}
			else if store.result != nil {
				HStack(spacing: 2) {
					HeaderButton(icon: "arrow.clockwise", tooltip: "Scan again", color: .blue) { send(.rescanTapped) }
					HeaderButton(icon: "internaldrive", tooltip: "Scan another volume or folder") { send(.newScanTapped) }
				}
				.headerCapsule()
			}
		}
		.padding()
		.windowTitleBarArea()
	}

	/// The folders from the scan root to the one on screen; each earlier one is a button back.
	private var breadcrumb: some View {
		ScrollView(.horizontal, showsIndicators: false) {
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
		.frame(maxWidth: 600)
	}

	private static func rootTitle(_ path: String) -> String {
		path == "/" ? "/" : URL(filePath: path).lastPathComponent
	}

	// MARK: - Content

	@ViewBuilder
	private var content: some View {
		switch store.scan {
		case .idle:
			VolumePickerView(volumes: store.volumes, onScan: { send(.scanRequested($0)) }, onChooseFolder: { send(.chooseFolderTapped) })
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
			ProgressView()
				.controlSize(.large)
			Text("Scanning \(root.path(percentEncoded: false))")
				.scaledFont(.title3)
				.fontWeight(.semibold)
			VStack(spacing: 4) {
				Text("\(progress.scannedBytes.formatted(.byteCount(style: .file))) in \(progress.scannedItems.formatted()) items")
					.monospacedDigit()
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
				.buttonStyle(.scaledBordered)
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}

	private func resultView(result: DiskScanResult, current: DiskNode) -> some View {
		let layout = SunburstLayout(center: current)
		return VStack(spacing: 0) {
			HStack(alignment: .top, spacing: 16) {
				SunburstChartView(
					layout: layout,
					canGoUp: store.path.count > 1,
					hovered: $hoveredSegment,
					selectedName: store.selectedName ?? hoveredName,
					onOpen: { send(.nodeOpened($0)) },
					onGoUp: { send(.pathIndexTapped(store.path.count - 2)) },
					onSelect: { send(.nodeSelected($0?.name)) }
				)
				.frame(minWidth: 280, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
				.padding(.leading)

				DiskChildrenList(
					node: current,
					layout: layout,
					selectedName: store.selectedName,
					hoveredName: hoveredSegment?.ancestry.first?.name ?? hoveredName,
					deletingName: store.deletingName,
					onHover: { hoveredName = $0 },
					onSelect: { send(.nodeSelected($0)) },
					onOpen: { send(.nodeOpened($0)) },
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
			.padding(.bottom, 8)

			footer(result: result)
		}
		// The mouse's back button goes up a folder, as clicking the chart's centre does.
		.onMouseBackButton {
			if store.path.count > 1 { send(.pathIndexTapped(store.path.count - 2)) }
		}
	}

	/// What is selected and what can be done with it, plus what the scan could not read.
	private func footer(result: DiskScanResult) -> some View {
		HStack(spacing: 12) {
			if let node = store.selectedNode {
				VStack(alignment: .leading, spacing: 2) {
					Text(node.name)
						.fontWeight(.semibold)
						.lineLimit(1)
						.truncationMode(.middle)
					Text(DiskNodeDescription.summary(of: node, within: store.currentNode))
						.foregroundStyle(.secondary)
						.monospacedDigit()
				}
				.scaledFont(.callout)

				Spacer()

				if store.deletingName == node.name {
					ProgressView()
						.controlSize(.small)
					Text("Removing…")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
				}
				else {
					Button {
						send(.showInFinderTapped)
					} label: {
						Label("Show in Finder", systemImage: "folder")
					}
					.buttonStyle(.scaledBordered)
					let isRemovable = node.isRemovable
					Button(role: .destructive) {
						send(.moveToTrashTapped)
					} label: {
						Label("Move to Trash…", systemImage: "trash")
					}
					.buttonStyle(.scaledBordered)
					.disabled(!isRemovable || store.deletingName != nil)
					Button("Delete…", role: .destructive) {
						send(.deletePermanentlyTapped)
					}
					.buttonStyle(.scaledBordered)
					.disabled(!isRemovable || store.deletingName != nil)
				}
			}
			else {
				Text(Self.summary(of: result))
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
					.monospacedDigit()
				Spacer()
				if result.inaccessibleFolders > 0 {
					Label(
						"\(result.inaccessibleFolders.formatted()) \(result.inaccessibleFolders == 1 ? "folder" : "folders") could not be read",
						systemImage: "lock"
					)
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
					Button("Grant Full Disk Access…") { send(.openFullDiskAccessSettingsTapped) }
						.buttonStyle(.scaledBordered)
						.controlSize(.small)
				}
			}
		}
		.padding(.horizontal)
		.padding(.vertical, 10)
		.background(Color(nsColor: .controlBackgroundColor))
	}

	private static func summary(of result: DiskScanResult) -> String {
		"\(result.root.size.formatted(.byteCount(style: .file))) in \(result.root.itemCount.formatted()) items, scanned in \(result.duration.formatted(.units(allowed: [.minutes, .seconds], width: .narrow)))"
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
		}
	}
}

private extension View {
	func headerCapsule() -> some View {
		padding(3)
			.glassEffect(.regular, in: .capsule)
	}
}

// MARK: - Volume picker

/// What to scan: a mounted volume, the home folder, or any folder.
struct VolumePickerView: View {
	let volumes: [DiskVolume]
	let onScan: (URL) -> Void
	let onChooseFolder: () -> Void

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				Text("Choose what to scan")
					.scaledFont(.title2)
					.fontWeight(.semibold)
				Text("The scan counts the space every folder takes, as Finder's Get Info does, and shows the result as rings around the folder you are looking at. Nothing is changed until you remove something yourself.")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
					ForEach(volumes) { volume in
						VolumeCard(volume: volume) { onScan(volume.url) }
					}
					FolderCard(
						title: "Home Folder",
						subtitle: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
						systemImage: "house",
						buttonTitle: "Scan"
					) {
						onScan(FileManager.default.homeDirectoryForCurrentUser)
					}
					FolderCard(
						title: "Any Folder",
						subtitle: "Pick a folder to scan",
						systemImage: "folder.badge.questionmark",
						buttonTitle: "Choose…",
						action: onChooseFolder
					)
				}
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

private struct VolumeCard: View {
	let volume: DiskVolume
	let onScan: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 10) {
				Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
					.scaledFont(.title2)
					.foregroundStyle(.secondary)
				VStack(alignment: .leading, spacing: 1) {
					Text(volume.name)
						.scaledFont(.headline)
						.lineLimit(1)
					Text(volume.isStartupVolume ? "Startup volume" : volume.url.path(percentEncoded: false))
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}
			CapacityBar(fraction: volume.usedFraction)
			HStack {
				Text("\(volume.usedCapacity.formatted(.byteCount(style: .file))) used of \(volume.totalCapacity.formatted(.byteCount(style: .file)))")
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
					.monospacedDigit()
				Spacer()
				Button("Scan", action: onScan)
					.buttonStyle(.scaledBorderedProminent)
					.controlSize(.small)
			}
		}
		.padding(12)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
	}
}

private struct FolderCard: View {
	let title: String
	let subtitle: String
	let systemImage: String
	let buttonTitle: String
	let action: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 10) {
				Image(systemName: systemImage)
					.scaledFont(.title2)
					.foregroundStyle(.secondary)
				VStack(alignment: .leading, spacing: 1) {
					Text(title)
						.scaledFont(.headline)
					Text(subtitle)
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}
			Spacer(minLength: 0)
			HStack {
				Spacer()
				Button(buttonTitle, action: action)
					.buttonStyle(.scaledBordered)
					.controlSize(.small)
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
	}
}

private struct CapacityBar: View {
	let fraction: Double

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .leading) {
				Capsule().fill(Color.primary.opacity(0.08))
				Capsule()
					.fill(fraction > 0.9 ? Color.red : fraction > 0.75 ? Color.orange : Color.accentColor)
					.frame(width: max(4, geometry.size.width * min(1, fraction)))
			}
		}
		.frame(height: 6)
	}
}

// MARK: - Children list

/// The contents of the folder on screen, largest first, each in its chart colour.
struct DiskChildrenList: View {
	let node: DiskNode
	let layout: SunburstLayout
	let selectedName: String?
	let hoveredName: String?
	let deletingName: String?
	let onHover: (String?) -> Void
	let onSelect: (String?) -> Void
	let onOpen: (DiskNode) -> Void
	let onShowInFinder: (String) -> Void
	let onMoveToTrash: (String) -> Void
	let onDelete: (String) -> Void

	@Environment(\.colorScheme)
	private var colorScheme

	var body: some View {
		ScrollView {
			LazyVStack(spacing: 2) {
				ForEach(node.children) { child in
					row(child)
				}
			}
			.padding(.trailing)
			.padding(.vertical, 4)
		}
		.onHover { isInside in
			if !isInside { onHover(nil) }
		}
	}

	private func row(_ child: DiskNode) -> some View {
		let isSelected = selectedName == child.name
		let isHovered = hoveredName == child.name
		let share = node.size > 0 ? Double(child.size) / Double(node.size) : 0
		return HStack(spacing: 8) {
			RoundedRectangle(cornerRadius: 2)
				.fill(swatchColor(for: child))
				.frame(width: 6, height: 22)
			Image(systemName: icon(for: child))
				.scaledFont(.callout)
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
			if deletingName == child.name {
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
			onSelect(isSelected ? nil : child.name)
		}
		.contextMenu {
			if child.isDirectory, !child.isInaccessible {
				Button("Open") { onOpen(child) }
			}
			if child.isOnDisk {
				Button("Show in Finder") { onShowInFinder(child.name) }
			}
			if child.isRemovable {
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
		}
	}

	/// The colour the chart gives the child; grey for one too small to be drawn.
	private func swatchColor(for child: DiskNode) -> Color {
		guard let segment = layout.segment(forChildNamed: child.name), !child.isInaccessible else {
			return Color.gray.opacity(0.45)
		}
		return Color(
			hue: SunburstLayout.hue(of: segment),
			saturation: child.isDirectory ? 0.62 : 0.4,
			brightness: colorScheme == .dark ? 0.8 : 0.92
		)
	}
}
