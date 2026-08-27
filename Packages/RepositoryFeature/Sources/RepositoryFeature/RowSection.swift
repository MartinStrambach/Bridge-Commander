import SwiftUI

/// A run of adjacent rows the list draws one header above.
///
/// What the rows split on follows the active ``SortMode``: sorting by state buckets them by
/// YouTrack state, sorting by ticket separates the ticketed rows from the ticketless ones. Sorting
/// by branch draws no headers — a branch name is already the row's own title, so a header per row
/// would only repeat it.
enum RowSection: Equatable {
	case ticketState(TicketStateSection)
	/// Every row carrying a ticket, while sorting by ticket. One section, not one per ticket:
	/// the ticket is already on the row.
	case tickets
	/// Every row carrying no ticket at all.
	case noTicket

	/// Returns `nil` in the sort modes that draw no headers.
	init?(row: RepositoryRowReducer.State, sortMode: SortMode) {
		switch sortMode {
		case .state: self = .ticketState(TicketStateSection(row: row))
		case .ticket: self = row.ticketId == nil ? .noTicket : .tickets
		case .branch: return nil
		}
	}

	var title: String {
		switch self {
		case let .ticketState(section): section.title
		case .tickets: "Tickets"
		case .noTicket: TicketStateSection.noTicket.title
		}
	}

	var color: Color {
		switch self {
		case let .ticketState(section): section.color
		// Neither section says anything about progress, so there is nothing to tint them with.
		case .noTicket,
		     .tickets: .secondary
		}
	}

	/// The header's background — the tint the ticket state used to paint whole rows with, or a
	/// neutral strip for the sections that never had one.
	var background: Color {
		switch self {
		case let .ticketState(section): section.background ?? Self.neutralBackground
		case .noTicket,
		     .tickets: Self.neutralBackground
		}
	}

	/// Enough to set a header apart from the rows under it, without claiming a state.
	private static let neutralBackground = Color.secondary.opacity(0.08)
}

/// A section header, and the rows it introduces.
struct RowSectionHeader: Equatable {
	let section: RowSection
	/// Rows in the contiguous run this header sits above — not every row in the section, so the
	/// count stays truthful while a YouTrack fetch has moved a row but the debounced re-sort hasn't
	/// landed yet.
	var count: Int
}

extension RepoGroupReducer.State {
	/// Where section headers go among this group's visible worktree rows, keyed by the id of the row
	/// each header sits above. Empty in the sort modes that draw no headers.
	///
	/// Runs are contiguous rather than one bucket per section: rows are already sorted into these
	/// buckets, but a YouTrack fetch can briefly reorder one ahead of the debounced re-sort, and a
	/// repeated header describes that in-between state correctly where a single misplaced row would
	/// not.
	func sectionHeaders(sortMode: SortMode, visibility: RowVisibility) -> [String: RowSectionHeader] {
		var runs: [(id: String, header: RowSectionHeader)] = []
		for row in worktrees where visibility.includesWorktree(id: row.id) {
			guard let section = RowSection(row: row, sortMode: sortMode) else {
				return [:]
			}

			if runs.last?.header.section == section {
				runs[runs.count - 1].header.count += 1
			}
			else {
				runs.append((id: row.id, header: RowSectionHeader(section: section, count: 1)))
			}
		}
		return Dictionary(uniqueKeysWithValues: runs)
	}
}
