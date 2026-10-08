import Foundation

/// What a page reducer of an instance (`HomerContinuationsReducer`, `HomerAgentsReducer`,
/// `HomerCostsReducer`) asks of the instance holding it.
public enum HomerPageDelegate: Equatable, Sendable {
	/// A call answered 401: the instance's session expired, and the instance signs out.
	case unauthorized
	/// A page of the web console, e.g. `agents/factory`, opened in the embedded browser sheet.
	case openWebConsole(path: String, title: String)
	/// A run's page, opened natively.
	case openProcess(processId: Int)
	/// The pending continuations changed here (a cancel): the badge's count is re-read rather
	/// than left to its next poll.
	case continuationsChanged
}

/// The instance's pages that have a reducer of their own. Each is told when it comes on screen
/// (`shown`) and goes off it (`hidden`), and polls only in between.
enum HomerChildPage: Equatable, Sendable {
	case continuations
	/// Agents and Schedules are one reducer — the schedules are the agents that have a cron —
	/// told which of the two is on screen, as an agent's page shows in place of either.
	case agents
	case schedules
	case costs

	init?(_ tab: HomerConsoleReducer.Tab) {
		switch tab {
		case .processes, .questions:
			return nil
		case .continuations:
			self = .continuations
		case .agents:
			self = .agents
		case .schedules:
			self = .schedules
		case .costs:
			self = .costs
		}
	}
}
