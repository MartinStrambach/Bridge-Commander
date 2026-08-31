import ComposableArchitecture
import Foundation

@Reducer
struct ShareButtonReducer {
	@ObservableState
	struct State: Equatable {
		private var branchName: String
		private var ticketURL: String
		private var prURL: String?

		var shareText: String {
			ShareButtonReducer.buildShareText(
				branchName: branchName,
				ticketURL: ticketURL,
				prURL: prURL
			)
		}

		init(branchName: String, ticketURL: String) {
			self.branchName = branchName
			self.ticketURL = ticketURL
		}

		mutating func updatePRURL(_ prURL: String?) {
			self.prURL = prURL
		}

		mutating func updateTicketURL(_ ticketURL: String) {
			self.ticketURL = ticketURL
		}
	}

	private static func buildShareText(branchName: String?, ticketURL: String?, prURL: String?) -> String {
		var shareTexts: [String] = []

		if let branchName, !branchName.isEmpty {
			shareTexts.append("Branch: \(branchName)")
		}

		// Empty means no ticket (or no YouTrack instance configured) — skip the line
		// rather than sharing a dangling "Ticket: ".
		if let ticketURL, !ticketURL.isEmpty {
			shareTexts.append("Ticket: \(ticketURL)")
		}

		if let prURL, !prURL.isEmpty {
			shareTexts.append("PR: \(prURL)")
		}

		guard !shareTexts.isEmpty else {
			return "no data to share"
		}

		return shareTexts.joined(separator: "\n")
	}
}
