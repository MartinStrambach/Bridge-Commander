import Foundation

/// What a page reducer of an instance (`HomerContinuationsReducer`, `HomerAgentsReducer`,
/// `HomerCostsReducer`) asks of the instance holding it.
public enum HomerPageDelegate: Equatable, Sendable {
	/// A call answered 401: the instance's session expired, and the instance signs out.
	case unauthorized
	/// A page of the web console, e.g. `processes/42`, opened in the embedded browser sheet.
	case openWebConsole(path: String, title: String)
}

/// The instance's pages that have a reducer of their own. Each is told when it comes on screen
/// (`shown`) and goes off it (`hidden`), and polls only in between.
enum HomerChildPage: Equatable, Sendable {
	case continuations
	/// Agents and Schedules: the schedules are the agents that have a cron.
	case agents
	case costs

	init?(_ tab: HomerConsoleReducer.Tab) {
		switch tab {
		case .processes, .questions:
			return nil
		case .continuations:
			self = .continuations
		case .agents, .schedules:
			self = .agents
		case .costs:
			self = .costs
		}
	}
}
