import ComposableArchitecture
import Foundation
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// Covers what the Create Worktree App Intent decides without a dialog to ask in: which branch
// to base a new one on, when to reuse an existing branch, and how the list reacts afterwards.
@Suite("External worktree creation")
@MainActor
struct ExternalWorktreeCreatorTests {
	private let branches = ["develop", "feature-x", "main", "master"]

	@Test("a new branch starts from master when nothing is configured")
	func newBranchUsesDefault() throws {
		let plan = try ExternalWorktreeCreator.plan(
			branchName: "feature-y",
			requestedBase: nil,
			available: branches,
			configuredDefault: ""
		)
		#expect(plan == .init(branchName: "feature-y", baseBranch: "master", createNewBranch: true))
	}

	@Test("the group's configured default branch wins over master")
	func newBranchUsesConfiguredDefault() throws {
		let plan = try ExternalWorktreeCreator.plan(
			branchName: "feature-y",
			requestedBase: nil,
			available: branches,
			configuredDefault: "develop"
		)
		#expect(plan.baseBranch == "develop")
	}

	@Test("a requested base branch is matched case-insensitively")
	func requestedBaseIsMatched() throws {
		let plan = try ExternalWorktreeCreator.plan(
			branchName: "feature-y",
			requestedBase: " Develop ",
			available: branches,
			configuredDefault: ""
		)
		#expect(plan.baseBranch == "develop")
	}

	@Test("a requested base branch that does not exist fails instead of falling back")
	func unknownRequestedBaseFails() {
		#expect(throws: ExternalWorktreeCreator.PlanError.unknownBaseBranch("release")) {
			try ExternalWorktreeCreator.plan(
				branchName: "feature-y",
				requestedBase: "release",
				available: branches,
				configuredDefault: ""
			)
		}
	}

	@Test("an existing branch is checked out rather than recreated")
	func existingBranchIsCheckedOut() throws {
		let plan = try ExternalWorktreeCreator.plan(
			branchName: "feature-x",
			requestedBase: "develop",
			available: branches,
			configuredDefault: ""
		)
		#expect(plan == .init(branchName: "feature-x", baseBranch: "feature-x", createNewBranch: false))
	}

	@Test("spoken whitespace becomes underscores, surrounding whitespace is dropped")
	func branchNameIsSanitized() throws {
		let plan = try ExternalWorktreeCreator.plan(
			branchName: "  fix login bug ",
			requestedBase: nil,
			available: branches,
			configuredDefault: ""
		)
		#expect(plan.branchName == "fix_login_bug")
	}

	@Test("an empty name or a repository without branches fails")
	func invalidInputFails() {
		#expect(throws: ExternalWorktreeCreator.PlanError.emptyBranchName) {
			try ExternalWorktreeCreator.plan(branchName: "   ", requestedBase: nil, available: branches, configuredDefault: "")
		}
		#expect(throws: ExternalWorktreeCreator.PlanError.noBranches) {
			try ExternalWorktreeCreator.plan(branchName: "x", requestedBase: nil, available: [], configuredDefault: "")
		}
	}

	@Test("a notification for an untracked root path changes nothing")
	func notificationForUnknownGroupIsIgnored() async {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		// Exhaustive: a scan started for a path that names no group fails here.
		await store.send(.view(.worktreeCreatedExternally(rootPath: "/repos/unknown")))
	}
}
