import ComposableArchitecture
import Foundation
import Testing
@testable import GitActionsMenu

@MainActor
struct GitActionsMenuMergePollingTests {

	/// Finishing a merge outside the app (e.g. `git commit` in the embedded terminal)
	/// fires no app action, so the reducer must notice MERGE_HEAD disappearing on its
	/// own and clear the merge banner.
	@Test
	func mergeStatusClearsWhenMergeFinishesOutsideTheApp() async throws {
		let fileManager = FileManager.default
		let repoPath = NSTemporaryDirectory() + "merge-polling-" + UUID().uuidString
		let gitDirectory = repoPath + "/.git"
		let mergeHeadPath = gitDirectory + "/MERGE_HEAD"
		try fileManager.createDirectory(atPath: gitDirectory, withIntermediateDirectories: true)
		fileManager.createFile(atPath: mergeHeadPath, contents: Data())
		defer { try? fileManager.removeItem(atPath: repoPath) }

		let clock = TestClock()
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: repoPath, currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		} withDependencies: {
			$0.continuousClock = clock
		}

		await store.send(.didCheckGitStatus(isMergeInProgress: true)) {
			$0.isMergeInProgress = true
		}

		// Merge still in progress: a poll tick must not emit anything.
		await clock.advance(by: .seconds(2))

		// The user finishes the merge in the terminal; git removes MERGE_HEAD.
		try fileManager.removeItem(atPath: mergeHeadPath)
		await clock.advance(by: .seconds(2))

		await store.receive(\.didCheckGitStatus) {
			$0.isMergeInProgress = false
		}
	}
}
