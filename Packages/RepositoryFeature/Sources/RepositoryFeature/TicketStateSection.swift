import SwiftUI
import ToolsIntegration

/// A bucket of rows that share a YouTrack state.
///
/// Single source of truth for the `SortMode.state` ordering: rows sort by declaration order here,
/// and ``RowSection`` heads each run of them with the same bucket — so a header can never disagree
/// with the order the rows are actually in.
enum TicketStateSection: Int, Comparable {
	case noTicket
	case open
	case inProgress
	case waitingToCodeReview
	case waitingForTesting
	/// A ticket whose state hasn't been fetched yet, or one YouTrack reports a state we don't model.
	case unknownState
	case waitingToAcceptation
	case accepted
	case done

	init(row: RepositoryRowReducer.State) {
		guard row.ticketId != nil else {
			self = .noTicket
			return
		}
		guard let ticketState = row.ticketState else {
			self = .unknownState
			return
		}

		switch ticketState {
		case .open: self = .open
		case .inProgress: self = .inProgress
		case .waitingToCodeReview: self = .waitingToCodeReview
		case .waitingForTesting: self = .waitingForTesting
		case .waitingToAcceptation: self = .waitingToAcceptation
		case .accepted: self = .accepted
		case .done: self = .done
		}
	}

	var title: String {
		switch self {
		case .noTicket: "No ticket"
		case .open: "Open"
		case .inProgress: "In progress"
		case .waitingToCodeReview: "Waiting to code review"
		case .waitingForTesting: "Waiting for testing"
		case .unknownState: "No state"
		case .waitingToAcceptation: "Waiting to acceptation"
		case .accepted: "Accepted"
		case .done: "Done"
		}
	}

	/// The tint this state used to paint whole rows with, back when the list colored rows instead of
	/// heading them — now the background of its header. `nil` for the states that never had one;
	/// those keep the neutral strip.
	var background: Color? {
		switch self {
		case .done: Color.mint.opacity(0.1)

		case .accepted,
		     .waitingToAcceptation: Color.blue.opacity(0.15)

		case .inProgress: Color.orange.opacity(0.1)

		case .noTicket,
		     .open,
		     .unknownState,
		     .waitingForTesting,
		     .waitingToCodeReview: nil
		}
	}

	/// The header's dot — the same hue as ``background`` at full strength, so the state reads even
	/// where the tint is faint.
	var color: Color {
		switch self {
		case .done: .mint

		case .accepted,
		     .waitingToAcceptation: .blue

		case .inProgress: .orange

		case .noTicket,
		     .open,
		     .unknownState,
		     .waitingForTesting,
		     .waitingToCodeReview: .secondary
		}
	}

	static func < (lhs: TicketStateSection, rhs: TicketStateSection) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}
