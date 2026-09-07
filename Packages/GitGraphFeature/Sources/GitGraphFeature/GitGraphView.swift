import AppKit
import ComposableArchitecture
import GitCore
import SwiftUI

public struct GitGraphView: View {
	@Bindable
	var store: StoreOf<GitGraphReducer>

	@Shared(.gitGraphColumnWidths)
	private var columnWidths = GitGraphColumnWidths()

	/// Live width override while a column divider is being dragged;
	/// the shared (persisted) value is only written once, on drag end.
	@State
	private var columnDrag: ColumnDrag?

	/// The list is centred on HEAD once per open, never again — see the scroll site below.
	@State
	private var hasScrolledToHead = false

	/// Focused on open so ↑/↓ walk the commits without having to click a row first.
	@FocusState
	private var isListFocused: Bool

	private struct ColumnDrag: Equatable {
		let column: GitGraphColumnWidths.Column
		let baseWidth: Double
		var proposedWidth: Double
	}

	private static let columnGap: CGFloat = 9

	public init(store: StoreOf<GitGraphReducer>) {
		self.store = store
	}

	public var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			content
		}
		.task {
			store.send(.task)
		}
	}

	// MARK: - Header

	private var header: some View {
		HStack {
			Text("Commit Graph")
				.font(.title2)
				.fontWeight(.semibold)

			Text(store.repositoryName)
				.font(.title3)
				.foregroundStyle(.secondary)

			Spacer()

			Button {
				store.send(.refreshButtonTapped)
			} label: {
				Image(systemName: "arrow.clockwise")
					.opacity(store.isLoading ? 0 : 1)
					.overlay {
						if store.isLoading {
							ProgressView()
								.scaleEffect(0.4)
						}
					}
			}
			.keyboardShortcut("r", modifiers: .command)
			.help(store.isLoading ? "Refreshing commits…" : "Refresh commits (⌘R)")
			.disabled(store.isLoading)

			Button("Close") {
				store.send(.closeButtonTapped)
			}
			.keyboardShortcut(.cancelAction)
		}
		.padding()
		.background(Color(nsColor: .windowBackgroundColor))
	}

	// MARK: - Content

	private var content: some View {
		VSplitView {
			graphPane
				.frame(minHeight: 160)

			if let detailStore = store.scope(\.commitDetail, action: \.commitDetail) {
				CommitDetailView(
					store: detailStore,
					onClose: { store.send(.closeDetailButtonTapped) }
				)
				.frame(minHeight: 200, idealHeight: 340)
			}
		}
	}

	@ViewBuilder
	private var graphPane: some View {
		if let errorMessage = store.errorMessage {
			errorView(message: errorMessage)
		}
		else if store.rows.isEmpty {
			VStack {
				Spacer()
				if store.isLoading {
					ProgressView("Loading commits…")
				}
				else {
					Text("No commits")
						.foregroundStyle(.secondary)
				}
				Spacer()
			}
			.frame(maxWidth: .infinity)
		}
		else {
			// A List rather than a ScrollView + LazyVStack, so selection is native: the list
			// takes focus on open, ↑/↓ walk the commits, and each move writes back through
			// `selection` — which is what loads the diff below.
			//
			// The column header stays a section header *inside* the list: a layout-taking
			// vertical scroller insets only the list's own content, so a header placed above
			// the list would be wider than the rows and the column boundaries would no longer
			// line up.
			ScrollViewReader { proxy in
				List(selection: selection) {
					Section {
						ForEach(store.rows) { row in
							GitGraphRowView(row: row, widths: effectiveWidths, columnGap: Self.columnGap)
								.tag(row.id)
								.listRowInsets(EdgeInsets())
								.listRowSeparator(.hidden)
						}

						if store.canLoadMore {
							Button("Load More") {
								store.send(.loadMoreButtonTapped)
							}
							.buttonStyle(.bordered)
							.controlSize(.small)
							.disabled(store.isLoading)
							.padding(.vertical, 12)
							.frame(maxWidth: .infinity)
							.listRowSeparator(.hidden)
							// Not a commit, so arrow keys must skip past it.
							.selectionDisabled()
						}
					} header: {
						VStack(spacing: 0) {
							columnHeader
							Divider()
						}
						.listRowInsets(EdgeInsets())
					}
				}
				.listStyle(.plain)
				.focused($isListFocused)
				// Rows draw their lane lines edge to edge, so the list must not pad them to a
				// taller default row — a gap would break the vertical lines between commits.
				.environment(\.defaultMinListRowHeight, GitGraphRowView.rowHeight)
				// One list-level menu driven by the selection. Per-row `.contextMenu` is
				// deliberately avoided: ⌘A is dispatched through `NSMenu
				// performKeyEquivalent:`, which makes AppKit build every row's menu, turning
				// select-all into O(rows^2) work (see FileChangeListView).
				.contextMenu(forSelectionType: GitGraphRow.ID.self) { ids in
					contextMenu(forSelection: ids)
				}
				.onAppear {
					// Refresh and Load More replace the rows without recreating the list, so
					// this normally fires once per open anyway. The flag pins that down:
					// selecting a commit adds a sibling pane to the enclosing VSplitView, and
					// a re-run would yank the list back to HEAD while the user is reading a
					// much older commit.
					guard !hasScrolledToHead else {
						return
					}

					hasScrolledToHead = true
					isListFocused = true
					guard let headRowID = store.rows.first(where: \.commit.isHead)?.id else {
						return
					}
					proxy.scrollTo(headRowID, anchor: .center)
				}
			}
		}
	}

	// MARK: - Selection

	private var selection: Binding<GitGraphRow.ID?> {
		Binding(
			get: { store.selectedCommitHash },
			set: { newValue in
				// A nil write is ignored on purpose. The list reports one when it cannot carry
				// the selection over a wholesale row replacement (a refresh, a Load More), and
				// closing the diff pane on a background reload would be baffling. The pane is
				// closed deliberately, with its own button.
				guard let newValue else {
					return
				}

				store.send(.commitTapped(newValue))
			}
		)
	}

	// Built lazily by AppKit only when a menu is actually requested (right-click), so the
	// lookup here runs once per interaction — never per row.
	@ViewBuilder
	private func contextMenu(forSelection ids: Set<GitGraphRow.ID>) -> some View {
		if let id = ids.first, let commit = store.rows.first(where: { $0.id == id })?.commit {
			Button("Copy Commit Hash") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(commit.hash, forType: .string)
			}
			Button("Copy Commit Message") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(commit.subject, forType: .string)
			}
		}
	}

	private func errorView(message: String) -> some View {
		VStack(spacing: 16) {
			Spacer()
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.largeTitle)
				.foregroundColor(.red)
			Text("Failed to load commit history")
				.font(.headline)
			Text(message)
				.font(.caption)
				.foregroundStyle(.secondary)
				.textSelection(.enabled)
			Button("Retry") {
				store.send(.refreshButtonTapped)
			}
			.buttonStyle(.borderedProminent)
			Spacer()
		}
		.frame(maxWidth: .infinity)
	}

	// MARK: - Column Header

	private var effectiveWidths: GitGraphColumnWidths {
		guard let columnDrag else {
			return columnWidths
		}
		var widths = columnWidths
		widths[columnDrag.column] = columnDrag.proposedWidth
		return widths
	}

	private var columnHeader: some View {
		let widths = effectiveWidths
		return HStack(spacing: 0) {
			columnTitle("Graph")
				.frame(width: widths.graph, alignment: .leading)
			resizeHandle(for: .graph, sign: 1)

			columnTitle("Description")
				.frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)
			resizeHandle(for: .author, sign: -1)

			columnTitle("Author")
				.frame(width: widths.author, alignment: .leading)
			resizeHandle(for: .date, sign: -1)

			columnTitle("Date")
				.frame(width: widths.date, alignment: .leading)
			resizeHandle(for: .hash, sign: -1)

			columnTitle("Hash")
				.frame(width: widths.hash, alignment: .leading)
		}
		.padding(.trailing, 12)
		.frame(height: 24)
		.background(Color(nsColor: .windowBackgroundColor))
	}

	private func columnTitle(_ title: String) -> some View {
		Text(title)
			.font(.caption)
			.fontWeight(.medium)
			.foregroundStyle(.secondary)
			.lineLimit(1)
			.padding(.leading, 4)
	}

	/// A draggable divider between two columns. The description column is
	/// flexible, so the columns right of it are anchored to the trailing edge:
	/// their left boundary follows the cursor when the width changes with the
	/// opposite sign (dragging right shrinks the column, growing the description).
	private func resizeHandle(for column: GitGraphColumnWidths.Column, sign: Double) -> some View {
		Rectangle()
			.fill(Color(nsColor: .separatorColor))
			.frame(width: 1)
			.frame(width: Self.columnGap)
			.contentShape(Rectangle())
			.pointerStyle(.columnResize)
			.gesture(
				// The handle moves as the column resizes, so translation must be
				// measured in a stable coordinate space — with .local the moving
				// view's own displacement feeds back into the translation and the
				// width oscillates while dragging.
				DragGesture(minimumDistance: 1, coordinateSpace: .global)
					.onChanged { value in
						let base = columnDrag?.column == column
							? (columnDrag?.baseWidth ?? columnWidths[column])
							: columnWidths[column]
						columnDrag = ColumnDrag(
							column: column,
							baseWidth: base,
							proposedWidth: (base + sign * value.translation.width).rounded()
						)
					}
					.onEnded { value in
						let base = columnDrag?.baseWidth ?? columnWidths[column]
						$columnWidths.withLock {
							$0[column] = (base + sign * value.translation.width).rounded()
						}
						columnDrag = nil
					}
			)
	}
}

// MARK: - Row

private struct GitGraphRowView: View {
	let row: GitGraphRow
	let widths: GitGraphColumnWidths
	let columnGap: CGFloat

	/// Read by the list to keep rows flush, so the lane lines join up between commits.
	static let rowHeight: CGFloat = 26

	private static let laneWidth: CGFloat = 14

	private static let laneColors: [Color] = [
		.blue, .green, .orange, .purple, .pink, .teal,
		.red, .yellow, .indigo, .mint, .cyan, .brown
	]

	var body: some View {
		HStack(spacing: 0) {
			graphCell
				.frame(width: widths.graph, height: Self.rowHeight)
				.clipped()
			columnSpacer

			HStack(spacing: 6) {
				ForEach(row.commit.refs, id: \.self) { ref in
					refChip(ref)
				}

				Text(row.commit.subject)
					.font(.callout)
					.fontWeight(row.commit.isHead ? .semibold : .regular)
					.lineLimit(1)
					.truncationMode(.tail)
			}
			.padding(.leading, 4)
			.frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)
			columnSpacer

			Text(row.commit.author)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.padding(.leading, 4)
				.frame(width: widths.author, alignment: .leading)
			columnSpacer

			Text(row.commit.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.padding(.leading, 4)
				.frame(width: widths.date, alignment: .leading)
			columnSpacer

			Text(row.commit.shortHash)
				.font(.system(.caption, design: .monospaced))
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.padding(.leading, 4)
				.frame(width: widths.hash, alignment: .leading)
		}
		.padding(.trailing, 12)
		.frame(height: Self.rowHeight)
		// The selected row's fill is the list's own. This tint only marks HEAD, and stays
		// translucent so it reads as a tint over that fill rather than hiding it.
		.background {
			if row.commit.isHead {
				Color.accentColor.opacity(0.12)
			}
		}
		// The whole row is the hit target, including the gaps between columns.
		.contentShape(Rectangle())
	}

	private var columnSpacer: some View {
		Color.clear.frame(width: columnGap)
	}

	// MARK: - Graph Cell

	private var graphCell: some View {
		Canvas { context, size in
			let midY = size.height / 2
			let lineWidth: CGFloat = 2

			for column in row.passThroughColumns {
				var path = Path()
				path.move(to: CGPoint(x: x(column), y: 0))
				path.addLine(to: CGPoint(x: x(column), y: size.height))
				context.stroke(path, with: .color(color(column)), lineWidth: lineWidth)
			}

			for column in row.incomingColumns {
				var path = Path()
				path.move(to: CGPoint(x: x(column), y: 0))
				path.addCurve(
					to: CGPoint(x: x(row.column), y: midY),
					control1: CGPoint(x: x(column), y: midY * 0.5),
					control2: CGPoint(x: x(row.column), y: midY * 0.5)
				)
				context.stroke(path, with: .color(color(column)), lineWidth: lineWidth)
			}

			for column in row.outgoingColumns {
				var path = Path()
				path.move(to: CGPoint(x: x(row.column), y: midY))
				path.addCurve(
					to: CGPoint(x: x(column), y: size.height),
					control1: CGPoint(x: x(row.column), y: (midY + size.height) / 2),
					control2: CGPoint(x: x(column), y: (midY + size.height) / 2)
				)
				context.stroke(path, with: .color(color(column)), lineWidth: lineWidth)
			}

			let dotRadius: CGFloat = row.commit.isMerge ? 3 : 4
			let dotRect = CGRect(
				x: x(row.column) - dotRadius,
				y: midY - dotRadius,
				width: dotRadius * 2,
				height: dotRadius * 2
			)
			context.fill(Path(ellipseIn: dotRect), with: .color(color(row.column)))

			if row.commit.isHead {
				context.stroke(
					Path(ellipseIn: dotRect.insetBy(dx: -2.5, dy: -2.5)),
					with: .color(color(row.column)),
					lineWidth: 1.5
				)
			}
		}
	}

	private func x(_ column: Int) -> CGFloat {
		(CGFloat(column) + 0.5) * Self.laneWidth
	}

	private func color(_ column: Int) -> Color {
		Self.laneColors[column % Self.laneColors.count]
	}

	// MARK: - Ref Chips

	private func refChip(_ ref: GitCommitRef) -> some View {
		HStack(spacing: 3) {
			Image(systemName: refIcon(ref.kind))
				.font(.system(size: 8))
			Text(ref.name)
				.font(.caption2)
				.fontWeight(ref.isHead ? .bold : .medium)
				.lineLimit(1)
		}
		.padding(.horizontal, 6)
		.padding(.vertical, 2)
		.background(refColor(ref.kind).opacity(ref.isHead ? 1 : 0.18), in: Capsule())
		.foregroundStyle(ref.isHead ? Color.white : refColor(ref.kind))
	}

	private func refIcon(_ kind: GitCommitRef.Kind) -> String {
		switch kind {
		case .localBranch:
			"arrow.triangle.branch"
		case .remoteBranch:
			"network"
		case .tag:
			"tag"
		case .detachedHead:
			"smallcircle.filled.circle"
		}
	}

	private func refColor(_ kind: GitCommitRef.Kind) -> Color {
		switch kind {
		case .localBranch:
			.blue
		case .remoteBranch:
			.purple
		case .tag:
			.orange
		case .detachedHead:
			.red
		}
	}
}
