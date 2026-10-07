import Foundation

// What the Agents page offers whom: the console's `can(action, agentName?)`
// (`lib/auth/use-can.ts`), beside `canKill`/`canRetry`. It only decides which buttons to show —
// the server checks every call again.
extension HomerUser {
	/// Run is offered only to a user the server lets run the agent (a `run` grant). The console
	/// shows its Run button to everyone the agent is listed for — any grant — and lets the
	/// server refuse a read-only user with a 403.
	public func canRun(_ agent: HomerAgent) -> Bool {
		isGranted("run", on: agent.name)
	}

	/// Edit (the web console's file editor, which also holds the debug runs) — offered as the
	/// console offers it: a writable agent and an `edit` grant on it.
	public func canEdit(_ agent: HomerAgent) -> Bool {
		agent.isWritable && isGranted("edit", on: agent.name)
	}

	/// "New Agent" — an `edit` grant on some agent pattern, the server's condition for creating
	/// an agent of a matching name. The console shows it to everyone.
	public var canCreateAgents: Bool {
		isGranted("edit", on: nil)
	}

	/// "Reload" re-reads every agent definition: admins only, in the console and on the server.
	public var canReloadAgents: Bool {
		isAdmin
	}

	/// `can(action, agentName)`: an admin may do anything; anyone else needs a grant with the
	/// action whose agent pattern matches the agent — or, with no agent named, any grant with
	/// the action.
	func isGranted(_ action: String, on agentName: String?) -> Bool {
		if isAdmin {
			return true
		}
		return grants.contains { grant in
			guard grant.actions.contains(action) else {
				return false
			}
			guard let agentName else {
				return true
			}
			return grant.agents.contains { Self.agentPattern($0, matches: agentName) }
		}
	}
}
