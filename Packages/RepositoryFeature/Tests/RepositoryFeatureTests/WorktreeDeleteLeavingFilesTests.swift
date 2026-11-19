import ComposableArchitecture
import Foundation
import GitCore
import Settings
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The whole delete, against a real repository: the row's Remove, a `git worktree remove` that
// exits with an error after unregistering the worktree (a file it could not delete), and a
// terminal open in that worktree. Before 2026-11-17 this showed an error that vanished with the
// row on the next rescan, and the terminal ran on and kept notifying.
@Suite("Deleting a worktree git cannot fully delete")
@MainActor
struct WorktreeDeleteLeavingFilesTests {
	@Test("the delete ends with a warning, its tabs closed, the branch gone and the row kept for the alert")
	func deleteLeavingFilesClosesTabs() async throws {
		let repository = try Repository()
		defer { repository.remove() }
		// Off, so the delete never looks into the machine's real DerivedData.
		@Shared(.deleteDerivedDataOnWorktreeDelete) var deletesDerivedData = true
		$deletesDerivedData.withLock { $0 = false }

		// Paths as git reports them (`/private/var/…`), as the app's own scan would have them.
		let rows = await GitWorktreeScanner.listWorktrees(forRepo: repository.path)
		let main = try #require(rows.first { !$0.isWorktree })
		let worktree = try #require(rows.first { $0.isWorktree })
		try repository.addUndeletableFile(inWorktreeAt: worktree.path)

		let mainTab = TerminalSession(repositoryPath: main.path)
		let worktreeTab = TerminalSession(repositoryPath: worktree.path)
		var initialState = RepositoryListReducer.State()
		initialState.terminalSessions = [mainTab, worktreeTab]
		var layout = TerminalLayoutReducer.State()
		layout.activate(worktreeTab)
		initialState.terminalLayout = layout
		let store = TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[XcodeClient.self].projectGenerator = { _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: main.path, rows: rows))

		func row(_ action: DeleteWorktreeButtonReducer.Action) -> RepositoryListReducer.Action {
			.repositoryGroups(.element(
				id: main.path,
				action: .worktrees(.element(id: worktree.path, action: .deleteWorktreeButton(action)))
			))
		}
		var deleteButton: DeleteWorktreeButtonReducer.State? {
			store.state.repositoryGroups[id: main.path]?.worktrees[id: worktree.path]?.deleteWorktreeButton
		}

		await store.send(row(.showConfirmation))
		await store.send(row(.confirmationSheet(.presented(.confirmTapped(forceRemoval: true, deleteLocalBranch: true)))))
		await store.receive(
			\.repositoryGroups[id: main.path].worktrees[id: worktree.path].deleteWorktreeButton.didRemoveSuccessfullyWithWarning,
			timeout: .seconds(30)
		)

		#expect(store.state.terminalSessions.map(\.id) == [mainTab.id])
		#expect(store.state.terminalLayout?.activeSessionId == mainTab.id)
		#expect(deleteButton?.errorAlert == nil)
		#expect(deleteButton?.removalWarningAlert != nil)
		// The cleanup after the removal ran too.
		#expect(try repository.git("branch", "--list", "feature").isEmpty)

		// The watcher's rescan, which no longer finds the worktree, leaves the alert its row.
		let rescanned = await GitWorktreeScanner.listWorktrees(forRepo: repository.path)
		#expect(!rescanned.contains { $0.isWorktree })
		await store.send(.didScanGroup(rootPath: main.path, rows: rescanned))
		#expect(deleteButton?.removalWarningAlert != nil)
	}

	/// A repository on `main` with a linked worktree on `feature`.
	private struct Repository {
		let root: String
		let path: String

		init() throws {
			root = NSTemporaryDirectory() + "WorktreeDeleteLeavingFilesTests-" + UUID().uuidString
			path = root + "/repo"
			try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
			try git("init", "--initial-branch=main")
			try git("config", "user.email", "test@example.com")
			try git("config", "user.name", "Test")
			try git("config", "commit.gpgsign", "false")
			try git("commit", "--allow-empty", "-m", "base")
			try git("worktree", "add", "-b", "feature", root + "/worktree")
		}

		@discardableResult
		func git(_ arguments: String...) throws -> String {
			let process = Process()
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = arguments
			process.currentDirectoryURL = URL(filePath: path)
			let output = Pipe()
			process.standardOutput = output
			process.standardError = Pipe()
			try process.run()
			let data = output.fileHandleForReading.readDataToEndOfFile()
			process.waitUntilExit()
			guard process.terminationStatus == 0 else {
				throw GitError.logFailed("git \(arguments.joined(separator: " "))")
			}
			return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
		}

		/// A folder whose file cannot be deleted, as one a running program holds.
		func addUndeletableFile(inWorktreeAt worktreePath: String) throws {
			let folder = worktreePath + "/locked"
			try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
			try "kept".write(toFile: folder + "/file", atomically: true, encoding: .utf8)
			try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
		}

		func remove() {
			try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/worktree/locked")
			try? FileManager.default.removeItem(atPath: root)
		}
	}
}
