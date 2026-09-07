import ComposableArchitecture
import SwiftUI
import AppUI
import TerminalFeature

struct SidebarRepositoryRowView: View {
	@State private var showKillConfirmation = false

	/// A store rather than a plain value: the badges below are refreshed counts, and a value
	/// read out of the parent's `IdentifiedArray` would be frozen at whenever that parent last
	/// rebuilt (TCA compares element ids only). Same wiring as the list's `RepositoryRowView`.
	let store: StoreOf<RepositoryRowReducer>
	let isActive: Bool
	let sessionStatus: TerminalSessionStatus?
	let onTap: () -> Void
	var onKill: (() -> Void)?

	var hasTerminalSession: Bool {
		sessionStatus != nil
	}

	var body: some View {
		Button(action: onTap) {
			HStack(spacing: 8) {
				// Terminal-active indicator dot
				TerminalStatusDotView(status: sessionStatus, size: 12)

				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 4) {
						if let ticketId = store.ticketId {
							Text(ticketId)
								.font(.caption2)
								.fontWeight(.medium)
								.foregroundStyle(.secondary)
								.lineLimit(1)
								.padding(.horizontal, 4)
								.padding(.vertical, 1)
								.background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
						}
						Text(store.formattedBranchName)
							.font(.caption)
							.fontWeight(isActive ? .semibold : .regular)
							.lineLimit(1)
							.foregroundColor(isActive ? .primary : .secondary)
					}

					Text(store.name)
						.font(.caption2)
						.foregroundColor(.secondary)
						.lineLimit(1)
				}

				Spacer()

				// Change count badges
				HStack(spacing: 4) {
					if store.stagedChangesCount > 0 {
						Text("\(store.stagedChangesCount)")
							.font(.caption2)
							.foregroundColor(.green)
					}
					if store.unstagedChangesCount > 0 {
						Text("\(store.unstagedChangesCount)")
							.font(.caption2)
							.foregroundColor(.orange)
					}
					if store.unpushedCommitCount > 0 {
						Text("\(store.unpushedCommitCount)")
							.font(.caption2)
							.foregroundColor(.red)
					}
				}
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 6)
			.background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
			.cornerRadius(6)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.contextMenu {
			if hasTerminalSession, onKill != nil {
				Button("Kill Terminal", role: .destructive) {
					showKillConfirmation = true
				}
			}
		}
		.confirmationDialog("Kill Terminal?", isPresented: $showKillConfirmation) {
			if let onKill {
				Button("Kill Terminal", role: .destructive, action: onKill)
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("This will terminate the terminal session for \"\(store.name)\".")
		}
	}
}
