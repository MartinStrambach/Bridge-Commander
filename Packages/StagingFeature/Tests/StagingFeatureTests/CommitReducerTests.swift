import AppUI
import ComposableArchitecture
import Foundation
import GitCore
import Testing
@testable import StagingFeature

// "Commit & Push" used to treat a failed push like a failed commit: the sheet showed the error
// and stayed open with the message, and the panel was never told the commit had landed. It kept
// listing the committed files as staged, and Commit made a second commit from the same message.
@Suite("Commit sheet")
@MainActor
struct CommitReducerTests {

	private struct GitFailure: LocalizedError {
		let errorDescription: String?
	}

	private func makeStore(
		commits: LockIsolated<Int>,
		dismissed: LockIsolated<Bool>,
		commit: @escaping @Sendable () async throws -> Void = {},
		push: @escaping @Sendable () async throws -> Void = {}
	) -> TestStoreOf<CommitReducer> {
		var state = CommitReducer.State(repositoryPath: "/repo")
		state.message = "Fix the thing"
		return TestStore(initialState: state) {
			CommitReducer()
		} withDependencies: {
			$0[GitStagingClient.self].commit = { _, _ in
				commits.withValue { $0 += 1 }
				try await commit()
			}
			$0[GitClient.self].push = { _ in
				try await push()
				return GitPushHelper.PushResult(isUpToDate: false, message: "")
			}
			$0.dismiss = DismissEffect { dismissed.setValue(true) }
		}
	}

	@Test("a push that fails after the commit landed still reports the commit, and acknowledging it closes the sheet")
	func failedPushStillReportsTheCommit() async {
		let commits = LockIsolated(0)
		let dismissed = LockIsolated(false)
		let store = makeStore(
			commits: commits,
			dismissed: dismissed,
			push: { throw GitFailure(errorDescription: "rejected: non-fast-forward") }
		)

		await store.send(.commitAndPushTapped) {
			$0.isCommitting = true
			$0.shouldPushAfterCommit = true
		}
		await store.receive(\.commitCompleted)
		await store.receive(\.pushCompleted) {
			$0.isCommitting = false
			$0.hasCommitted = true
			$0.alert = ScrollableAlertReducer.State(
				title: "Push Failed",
				message: "rejected: non-fast-forward",
				isError: true
			)
		}
		await store.receive(\.delegate.commitSucceeded)

		// The same message must not make a second commit, even if a tap gets through.
		await store.send(.commitTapped)
		await store.send(.commitAndPushTapped)
		#expect(commits.value == 1)
		#expect(!dismissed.value, "the push error is shown before the sheet closes")

		await store.send(.alert(.dismiss)) {
			$0.alert = nil
		}
		await store.finish()
		#expect(dismissed.value)
	}

	@Test("a failed commit keeps the sheet open with its message once the alert is acknowledged")
	func failedCommitKeepsTheSheetOpen() async {
		let commits = LockIsolated(0)
		let dismissed = LockIsolated(false)
		let store = makeStore(
			commits: commits,
			dismissed: dismissed,
			commit: { throw GitFailure(errorDescription: "nothing to commit") }
		)

		await store.send(.commitTapped) {
			$0.isCommitting = true
		}
		await store.receive(\.commitCompleted) {
			$0.isCommitting = false
			$0.alert = ScrollableAlertReducer.State(
				title: "Commit Failed",
				message: "nothing to commit",
				isError: true
			)
		}
		await store.send(.alert(.dismiss)) {
			$0.alert = nil
		}
		await store.finish()
		#expect(!dismissed.value)
		#expect(store.state.message == "Fix the thing")
	}

	@Test("a second tap while a commit is running does not start another commit")
	func doubleTapCommitsOnce() async {
		let commits = LockIsolated(0)
		let dismissed = LockIsolated(false)
		let gate = AsyncStream.makeStream(of: Void.self)
		let store = makeStore(
			commits: commits,
			dismissed: dismissed,
			commit: { for await _ in gate.stream {} }
		)

		await store.send(.commitTapped) {
			$0.isCommitting = true
		}
		await store.send(.commitTapped)
		await store.send(.commitAndPushTapped)
		gate.continuation.finish()

		await store.receive(\.commitCompleted) {
			$0.isCommitting = false
		}
		await store.receive(\.delegate.commitSucceeded)
		await store.finish()
		#expect(commits.value == 1)
		#expect(dismissed.value)
	}
}
