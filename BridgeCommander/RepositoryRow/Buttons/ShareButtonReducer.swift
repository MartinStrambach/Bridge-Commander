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
	}

	private static func buildShareText(branchName: String?, ticketURL: String?, prURL: String?) -> String {
		var shareTexts: [String] = []

		if let branchName {
			shareTexts.append("Branch: \(branchName)")
		}

		if let ticketURL {
			shareTexts.append("Ticket: \(ticketURL)")
		}

		if let prURL {
			shareTexts.append("PR: \(prURL)")
		}

		guard !shareTexts.isEmpty else {
			return "no data to share"
		}

		return shareTexts.joined(separator: "\n")
	}
}
