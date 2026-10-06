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

	/// Set when the search changes, so the list scrolls once the results for it have loaded.
	/// Without it the list keeps its old offset, which in the new rows points at nothing in particular.
	@State
	private var scrollsAfterSearch = false

	/// Which list ↑/↓ drive. The commit list is focused on open so ↑/↓ walk the commits
	/// without having to click a row first; clicking a file (or →) hands focus to the file list.
	///
	/// Tracked explicitly rather than left to the click: with a plain Bool the commit list kept
	/// focus after a file was clicked, so ↑/↓ went on moving the commit selection.
	@FocusState
	private var focusedPane: GitGraphPane?

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
		.onChange(of: store.search) {
			scrollsAfterSearch = true
		}
		.alert($store.scope(\.$alert, action: \.alert))
		.sheet(item: branchFormBinding) { _ in
			BranchFormView(store: store)
		}
	}

	/// Dismissing the sheet any way other than its buttons cancels the form.
	private var branchFormBinding: Binding<BranchForm?> {
		Binding(
			get: { store.branchForm },
			set: { form in
				if form == nil, store.branchForm != nil {
					store.send(.commitAction(.branchFormCancelled))
				}
			}
		)
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

			if let runningCommitAction = store.runningCommitAction {
				ProgressView()
					.controlSize(.small)
				Text(runningCommitAction)
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			if store.search != nil, !store.isLoading, store.errorMessage == nil {
				Text(store.canLoadMore ? "\(store.rows.count)+ commits" : "^[\(store.rows.count) commit](inflect: true)")
					.font(.caption)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}

			searchField

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
		}
		.padding()
		.background(Color(nsColor: .windowBackgroundColor))
		.background {
			shortcuts
		}
	}

	// MARK: - Search

	private var searchField: some View {
		HStack(spacing: 6) {
			Picker(
				"Search in",
				selection: Binding(get: { store.searchField }, set: { store.send(.searchFieldChanged($0)) })
			) {
				ForEach(GitLogSearch.Field.allCases, id: \.self) { field in
					Text(field.title).tag(field)
				}
			}
			.labelsHidden()
			.pickerStyle(.menu)
			.fixedSize()
			.help(store.searchField.help)

			HStack(spacing: 4) {
				Image(systemName: "magnifyingglass")
					.foregroundStyle(.secondary)

				TextField(
					store.searchField.prompt,
					text: Binding(get: { store.searchQuery }, set: { store.send(.searchQueryChanged($0)) })
				)
				.textFieldStyle(.plain)
				.focused($focusedPane, equals: .search)
				// Return and ↓ go on to the results, the way they do from a search field elsewhere.
				.onSubmit {
					focusedPane = .commits
				}
				.onKeyPress(.downArrow) {
					focusedPane = .commits
					return .handled
				}

				if !store.searchQuery.isEmpty {
					Button {
						store.send(.searchQueryChanged(""))
					} label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.secondary)
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.help("Clear search")
				}
			}
			.padding(.horizontal, 7)
			.padding(.vertical, 4)
			.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
			.overlay {
				RoundedRectangle(cornerRadius: 6)
					.strokeBorder(Color(nsColor: .separatorColor))
			}
			.frame(width: 280)
		}
	}

	/// ⌘F and Escape, as hidden buttons so both stay registered whatever has focus.
	///
	/// Escape is here rather than on the Close button so it can clear the search first, as a
	/// search field does: while typing, a cancel shortcut on Close would close the sheet instead.
	/// Close itself cannot decide by focus — clicking it leaves the focus in the field.
	private var shortcuts: some View {
		ZStack {
			Button("") {
				focusedPane = .search
			}
			.keyboardShortcut("f", modifiers: .command)

			Button("") {
				if focusedPane == .search, !store.searchQuery.isEmpty {
					store.send(.searchQueryChanged(""))
				}
				else {
					store.send(.closeButtonTapped)
				}
			}
			.keyboardShortcut(.cancelAction)
		}
		.hidden()
	}

	// MARK: - Content

	private var content: some View {
		VSplitView {
			graphPane
				.frame(minHeight: 160)

			if let detailStore = store.scope(\.commitDetail, action: \.commitDetail) {
				CommitDetailView(
					store: detailStore,
					focusedPane: $focusedPane,
					onClose: {
						store.send(.closeDetailButtonTapped)
						focusedPane = .commits
					}
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
				else if let search = store.search {
					Text("No commits match “\(search.query)”")
						.foregroundStyle(.secondary)
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
								.contentShape(Rectangle())
								// Clicking the commit already selected changes no selection, so the
								// selection binding cannot take focus back from the file list; the tap can.
								.simultaneousGesture(TapGesture().onEnded { focusedPane = .commits })
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
				.focused($focusedPane, equals: .commits)
				.onKeyPress(.rightArrow) {
					guard store.commitDetail != nil else {
						return .ignored
					}

					focusedPane = .files
					return .handled
				}
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
						// Back after "No commits match": the rows and the end of loading arrived
						// together with the list, so the onChange below never saw them.
						scrollAfterSearch(proxy)
						return
					}

					hasScrolledToHead = true
					focusedPane = .commits
					guard let headRowID = store.rows.first(where: \.commit.isHead)?.id else {
						return
					}
					proxy.scrollTo(headRowID, anchor: .center)
				}
				.onChange(of: store.isLoading) { _, isLoading in
					if !isLoading {
						scrollAfterSearch(proxy)
					}
				}
			}
		}
	}

	/// Once a changed search has loaded: keeps the selected commit in view if it is still listed,
	/// otherwise goes to the top of the results, or back to HEAD when the search was cleared.
	private func scrollAfterSearch(_ proxy: ScrollViewProxy) {
		guard scrollsAfterSearch else {
			return
		}

		scrollsAfterSearch = false
		let selectedRowID = store.rows.first { $0.id == store.selectedCommitHash }?.id
		let fallbackRowID = store.search == nil
			? store.rows.first(where: \.commit.isHead)?.id
			: store.rows.first?.id
		guard let target = selectedRowID ?? fallbackRowID else {
			return
		}

		proxy.scrollTo(target, anchor: .center)
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
				// A click on a commit while the file list has focus must take focus back:
				// the new commit reloads the file list, which is swapped for a spinner while
				// loading, so the focused view vanishes and ↑/↓ would reach nothing.
				focusedPane = .commits
			}
		)
	}

	// Built lazily by AppKit only when a menu is actually requested (right-click), so the
	// lookup here runs once per interaction — never per row.
	@ViewBuilder
	private func contextMenu(forSelection ids: Set<GitGraphRow.ID>) -> some View {
		if let id = ids.first, let commit = store.rows.first(where: { $0.id == id })?.commit {
			// One write action at a time: a second git command started mid-way would fail on
			// the first one's index lock, or worse, act on a half-changed branch.
			Group {
				checkoutItems(for: commit)

				Divider()

				Button("New Branch from Commit…") {
					store.send(.commitAction(.newBranchTapped(commit)))
				}
				Button("New Worktree from Commit…") {
					store.send(.commitAction(.newWorktreeTapped(commit)))
				}

				Divider()

				// HEAD's own changes are already on the branch it would be picked onto.
				if !commit.isHead {
					Button("Cherry-Pick onto Current Branch…") {
						store.send(.commitAction(.cherryPickTapped(commit)))
					}
				}
				Button("Revert Commit…") {
					store.send(.commitAction(.revertTapped(commit)))
				}
			}
			.disabled(store.runningCommitAction != nil)

			Divider()

			Button("Copy Commit Hash") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(commit.hash, forType: .string)
			}
			Button("Copy Short Hash") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(commit.shortHash, forType: .string)
			}
			Button("Copy Commit Message") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(commit.subject, forType: .string)
			}
		}
	}

	/// The branches on this commit that can be checked out, then the commit itself.
	///
	/// A remote branch checks out its local namesake (created to track it when missing), so it is
	/// left out when that local branch is decorating the same commit and already has an item.
	@ViewBuilder
	private func checkoutItems(for commit: GitLogCommit) -> some View {
		let localBranches = commit.refs.filter { $0.kind == .localBranch }
		let localNames = Set(localBranches.map(\.name))
		let remoteBranches = commit.refs.filter { ref in
			guard
				ref.kind == .remoteBranch,
				let localName = GitCommitActionHelper.localBranchName(forRemoteBranch: ref.name)
			else {
				return false
			}

			return !localNames.contains(localName)
		}

		ForEach(localBranches.filter { !$0.isHead }, id: \.name) { branch in
			Button("Check Out “\(branch.name)”") {
				store.send(.commitAction(.checkoutBranchTapped(branch.name)))
			}
		}
		ForEach(remoteBranches, id: \.name) { branch in
			let localName = GitCommitActionHelper.localBranchName(forRemoteBranch: branch.name) ?? branch.name
			Button("Check Out “\(localName)” from \(branch.name)") {
				store.send(.commitAction(.checkoutRemoteBranchTapped(branch.name)))
			}
		}
		if !commit.isHead {
			Button("Check Out Commit (Detached HEAD)…") {
				store.send(.commitAction(.checkoutCommitTapped(commit)))
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

// MARK: - Branch Form

/// Names the branch for "New Branch…" / "New Worktree…".
private struct BranchFormView: View {
	let store: StoreOf<GitGraphReducer>

	@FocusState
	private var isNameFocused: Bool

	var body: some View {
		if let form = store.branchForm {
			VStack(alignment: .leading, spacing: 14) {
				VStack(alignment: .leading, spacing: 4) {
					Text(form.kind == .branch ? "New Branch" : "New Worktree")
						.font(.headline)
					Text("From \(form.commit.shortHash) “\(form.commit.subject)”")
						.font(.callout)
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}

				TextField(
					"Branch name",
					text: Binding(get: { form.name }, set: { store.send(.commitAction(.branchFormNameChanged($0))) })
				)
				.textFieldStyle(.roundedBorder)
				.focused($isNameFocused)
				.onSubmit {
					store.send(.commitAction(.branchFormSubmitted))
				}

				switch form.kind {
				case .branch:
					Toggle(
						"Check out the new branch",
						isOn: Binding(get: { form.checksOut }, set: { store.send(.commitAction(.branchFormChecksOutChanged($0))) })
					)

				case .worktree:
					Text(worktreeFolder(for: form))
						.font(.caption)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
						.lineLimit(2)
						.truncationMode(.middle)
				}

				HStack {
					Spacer()
					Button("Cancel", role: .cancel) {
						store.send(.commitAction(.branchFormCancelled))
					}
					.keyboardShortcut(.cancelAction)

					Button(form.kind == .branch ? "Create Branch" : "Create Worktree") {
						store.send(.commitAction(.branchFormSubmitted))
					}
					.keyboardShortcut(.defaultAction)
					.disabled(!form.canSubmit)
				}
			}
			.padding(20)
			.frame(width: 440)
			.onAppear {
				isNameFocused = true
			}
		}
	}

	private func worktreeFolder(for form: BranchForm) -> String {
		guard form.canSubmit else {
			return "Created next to the repository’s other worktrees"
		}

		let folder = GitWorktreeCreator.worktreeFolder(
			repositoryPath: store.mainRepositoryPath,
			branchName: form.branchName,
			baseBranch: "",
			createNewBranch: true,
			worktreeBasePath: store.worktreeBasePath
		)
		return "Created in \(folder.path)"
	}
}

// MARK: - Search Field Labels

private extension GitLogSearch.Field {
	var title: String {
		switch self {
		case .message:
			"Message"
		case .author:
			"Author"
		case .hash:
			"Hash"
		case .path:
			"File Path"
		case .content:
			"Changes"
		}
	}

	var prompt: String {
		switch self {
		case .message:
			"Search commit messages (⌘F)"
		case .author:
			"Search author names and emails"
		case .hash:
			"Commit hash or prefix"
		case .path:
			"Search changed file paths"
		case .content:
			"Text added or removed"
		}
	}

	var help: String {
		switch self {
		case .message:
			"Commits whose message contains the text (git log --grep)"
		case .author:
			"Commits whose author name or email contains the text (git log --author)"
		case .hash:
			"The commit with this hash, full or abbreviated"
		case .path:
			"Commits that changed a file or folder whose path contains the text (git log -- <path>)"
		case .content:
			"Commits that add or remove the text (git log -S)"
		}
	}
}
