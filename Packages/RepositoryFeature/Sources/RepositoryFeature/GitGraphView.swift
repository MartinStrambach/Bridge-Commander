import AppKit
import ComposableArchitecture
import GitCore
import Settings
import SwiftUI

struct GitGraphView: View {
	@Bindable
	var store: StoreOf<GitGraphReducer>

	@Shared(.gitGraphColumnWidths)
	private var columnWidths = GitGraphColumnWidths()

	/// Live width override while a column divider is being dragged;
	/// the shared (persisted) value is only written once, on drag end.
	@State
	private var columnDrag: ColumnDrag?

	private struct ColumnDrag: Equatable {
		let column: GitGraphColumnWidths.Column
		let baseWidth: Double
		var proposedWidth: Double
	}

	private static let columnGap: CGFloat = 9

	var body: some View {
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

	@ViewBuilder
	private var content: some View {
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
			// The column header lives inside the ScrollView as a pinned section
			// header: a layout-taking vertical scroller insets only the scroll
			// content, so a header outside would be wider than the rows and the
			// column boundaries would no longer line up.
			ScrollView {
				LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
					Section {
						ForEach(store.rows) { row in
							GitGraphRowView(row: row, widths: effectiveWidths, columnGap: Self.columnGap)
						}

						if store.canLoadMore {
							Button("Load More") {
								store.send(.loadMoreButtonTapped)
							}
							.buttonStyle(.bordered)
							.controlSize(.small)
							.disabled(store.isLoading)
							.padding(.vertical, 12)
						}
					} header: {
						VStack(spacing: 0) {
							columnHeader
							Divider()
						}
					}
				}
			}
			.background(Color(nsColor: .textBackgroundColor))
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

	private static let rowHeight: CGFloat = 26
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
		.contextMenu {
			Button("Copy Commit Hash") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(row.commit.hash, forType: .string)
			}
			Button("Copy Commit Message") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(row.commit.subject, forType: .string)
			}
		}
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
		.background(refColor(ref.kind).opacity(ref.isHead ? 0.35 : 0.18), in: Capsule())
		.overlay {
			if ref.isHead {
				Capsule().strokeBorder(refColor(ref.kind), lineWidth: 1)
			}
		}
		.foregroundStyle(refColor(ref.kind))
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
