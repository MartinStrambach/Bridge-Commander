import ComposableArchitecture
import Foundation
import GitCore
import Testing

@testable import GitGraphFeature

// Typing in the graph's search field narrows the graph to the matching commits. These tests pin
// down when a search runs and with what; the matching itself is git's (`GitLogClient`, stubbed).
@Suite("Graph search")
@MainActor
struct GraphSearchTests {

	// MARK: - Fixtures

	private struct Request: Equatable {
		let limit: Int
		let search: GitLogSearch?
	}

	private let commits = [
		GitLogCommit(
			hash: "aaa",
			parents: [],
			author: "Author",
			date: Date(timeIntervalSince1970: 1_700_000_000),
			refs: [],
			subject: "fix: something"
		)
	]

	private let clock = TestClock()
	private let requests = LockIsolated<[Request]>([])

	private func store(
		searchField: GitLogSearch.Field = .message,
		searchQuery: String = "",
		commitLimit: Int = GitGraphReducer.pageSize
	) -> TestStoreOf<GitGraphReducer> {
		var state = GitGraphReducer.State(repositoryPath: "/tmp/repo", repositoryName: "repo")
		state.searchField = searchField
		state.searchQuery = searchQuery
		state.commitLimit = commitLimit

		return TestStore(initialState: state) {
			GitGraphReducer()
		} withDependencies: { [clock, requests, commits] in
			$0.continuousClock = clock
			$0[GitLogClient.self].loadCommits = { _, limit, search in
				requests.withValue { $0.append(Request(limit: limit, search: search)) }
				return commits
			}
		}
	}

	private func search(_ field: GitLogSearch.Field, _ query: String) -> GitLogSearch? {
		GitLogSearch(field: field, query: query)
	}

	private func receiveCommits(_ store: TestStoreOf<GitGraphReducer>) async {
		await store.receive(\.commitsLoaded) { [commits] in
			$0.isLoading = false
			$0.rows = GitGraphLayout.layout(commits: commits)
		}
	}

	// MARK: - Typing

	@Test("a query runs once typing pauses, from the first page")
	func queryRunsAfterTheDebounce() async {
		let store = store(commitLimit: 900)

		await store.send(.searchQueryChanged("fix")) {
			$0.searchQuery = "fix"
			$0.commitLimit = GitGraphReducer.pageSize
			$0.isLoading = true
		}
		await clock.advance(by: GitGraphReducer.searchDebounce - .milliseconds(1))
		#expect(requests.value.isEmpty)

		await clock.advance(by: .milliseconds(1))
		await receiveCommits(store)
		#expect(requests.value == [Request(limit: GitGraphReducer.pageSize, search: search(.message, "fix"))])
	}

	@Test("only the query typing paused on is searched")
	func keystrokesWithinTheDebounceCoalesce() async {
		let store = store()

		await store.send(.searchQueryChanged("f")) {
			$0.searchQuery = "f"
			$0.isLoading = true
		}
		await clock.advance(by: .milliseconds(100))
		await store.send(.searchQueryChanged("fi")) {
			$0.searchQuery = "fi"
		}
		await clock.advance(by: GitGraphReducer.searchDebounce)
		await receiveCommits(store)

		#expect(requests.value == [Request(limit: GitGraphReducer.pageSize, search: search(.message, "fi"))])
	}

	@Test("clearing the query brings the whole history back without waiting")
	func clearingLoadsTheWholeHistoryAtOnce() async {
		let store = store(searchQuery: "fix")

		await store.send(.searchQueryChanged("")) {
			$0.searchQuery = ""
			$0.isLoading = true
		}
		await receiveCommits(store)

		#expect(requests.value == [Request(limit: GitGraphReducer.pageSize, search: nil)])
	}

	// MARK: - Edits that change nothing

	@Test("edits that leave the search as it was load nothing")
	func unchangedSearchLoadsNothing() async {
		let store = store()

		// No query, so no search either way.
		await store.send(.searchFieldChanged(.author)) {
			$0.searchField = .author
		}
		await store.send(.searchQueryChanged("   ")) {
			$0.searchQuery = "   "
		}
		await clock.run()

		#expect(requests.value.isEmpty)
	}

	@Test("whitespace around the query does not search again")
	func surroundingWhitespaceDoesNotReload() async {
		let store = store(searchQuery: "fix")

		await store.send(.searchQueryChanged("fix ")) {
			$0.searchQuery = "fix "
		}
		await clock.run()

		#expect(requests.value.isEmpty)
	}

	// MARK: - Field

	@Test("switching the field searches the same query there")
	func switchingTheFieldRerunsTheQuery() async {
		let store = store(searchQuery: "alice")

		await store.send(.searchFieldChanged(.author)) {
			$0.searchField = .author
			$0.isLoading = true
		}
		await clock.advance(by: GitGraphReducer.searchDebounce)
		await receiveCommits(store)

		#expect(requests.value == [Request(limit: GitGraphReducer.pageSize, search: search(.author, "alice"))])
	}

	// MARK: - Paging

	@Test("Load More pages through the current search")
	func loadMoreKeepsTheSearch() async {
		let store = store(searchField: .path, searchQuery: "GitCore")

		await store.send(.loadMoreButtonTapped) {
			$0.commitLimit = GitGraphReducer.pageSize * 2
			$0.isLoading = true
		}
		await receiveCommits(store)

		#expect(requests.value == [Request(limit: GitGraphReducer.pageSize * 2, search: search(.path, "GitCore"))])
	}
}
