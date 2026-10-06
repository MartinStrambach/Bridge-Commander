import Foundation
import TerminalFeature

/// One repository or worktree as the menu bar extra lists it: where its branch stands against its
/// remote, and whether a terminal in it is waiting.
struct MenuBarRepositoryStatus: Equatable, Identifiable {
	enum Sync: Equatable {
		/// The first status fetch has not answered yet.
		case unknown
		/// No upstream to compare against.
		case unpublished
		case upToDate
		case diverged(ahead: Int, behind: Int)
	}

	let id: String
	let name: String
	let branchName: String?
	let isWorktree: Bool
	let sync: Sync
	let waitingSessionCount: Int

	init(row: RepositoryRowReducer.State, waitingSessionCount: Int) {
		self.id = row.path
		self.name = row.name
		self.branchName = row.branchName
		self.isWorktree = row.isWorktree
		self.waitingSessionCount = waitingSessionCount
		self.sync =
			if !row.hasFetchedStatus {
				.unknown
			}
			else if !row.hasRemoteBranch {
				.unpublished
			}
			else if row.unpushedCommitCount == 0, row.commitsBehindCount == 0 {
				.upToDate
			}
			else {
				.diverged(ahead: row.unpushedCommitCount, behind: row.commitsBehindCount)
			}
	}
}

/// A terminal tab waiting on the user, as the menu bar extra lists it.
struct MenuBarWaitingSession: Equatable, Identifiable {
	let id: UUID
	let location: String
}

extension RepositoryListReducer.State {
	/// Tabs waiting on the user: Claude at its prompt, or a program that asked for attention.
	var waitingSessions: [TerminalSession] {
		terminalSessions.filter { $0.status == .waitingForInput }
	}

	var menuBarWaitingSessions: [MenuBarWaitingSession] {
		waitingSessions.map { MenuBarWaitingSession(id: $0.id, location: tabLocation(for: $0)) }
	}

	/// Every row in the list's own order — each repository, then its worktrees — ignoring the
	/// list's filters and collapsed groups: the menu bar is the summary of all of them.
	var menuBarRepositories: [MenuBarRepositoryStatus] {
		var waitingByPath: [String: Int] = [:]
		for session in waitingSessions {
			waitingByPath[session.repositoryPath, default: 0] += 1
		}
		return repositoryGroups.flatMap { group in
			([group.header] + group.worktrees).map { row in
				MenuBarRepositoryStatus(row: row, waitingSessionCount: waitingByPath[row.path] ?? 0)
			}
		}
	}
}
