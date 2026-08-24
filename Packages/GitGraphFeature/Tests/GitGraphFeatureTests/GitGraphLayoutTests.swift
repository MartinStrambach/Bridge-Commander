import Foundation
import GitCore
import Testing
@testable import GitGraphFeature

@Suite("GitGraphLayout")
struct GitGraphLayoutTests {
	private func commit(_ hash: String, parents: [String] = []) -> GitLogCommit {
		GitLogCommit(
			hash: hash,
			parents: parents,
			author: "Author",
			date: Date(timeIntervalSince1970: 0),
			refs: [],
			subject: "Subject \(hash)"
		)
	}

	@Test("linear history stays in a single lane")
	func linearHistory() {
		let rows = GitGraphLayout.layout(commits: [
			commit("c2", parents: ["c1"]),
			commit("c1", parents: ["c0"]),
			commit("c0")
		])

		#expect(rows.map(\.column) == [0, 0, 0])
		#expect(rows[0].incomingColumns == [])
		#expect(rows[0].outgoingColumns == [0])
		#expect(rows[1].incomingColumns == [0])
		#expect(rows[1].outgoingColumns == [0])
		#expect(rows[2].incomingColumns == [0])
		#expect(rows[2].outgoingColumns == [])
		#expect(rows.allSatisfy { $0.passThroughColumns.isEmpty })
		#expect(GitGraphLayout.laneCount(rows: rows) == 1)
	}

	@Test("merge commit opens a second lane that converges at the fork point")
	func mergeDiamond() {
		// M merges A (first parent) and B; both branched from C
		let rows = GitGraphLayout.layout(commits: [
			commit("M", parents: ["A", "B"]),
			commit("A", parents: ["C"]),
			commit("B", parents: ["C"]),
			commit("C")
		])

		#expect(rows.map(\.column) == [0, 0, 1, 0])

		// Merge commit sends its second parent to lane 1
		#expect(rows[0].outgoingColumns == [0, 1])

		// A passes lane 1 through; B passes lane 0 through
		#expect(rows[1].passThroughColumns == [1])
		#expect(rows[2].passThroughColumns == [0])

		// Both lanes converge into the fork point C
		#expect(rows[3].incomingColumns == [0, 1])
		#expect(rows[3].outgoingColumns == [])
		#expect(GitGraphLayout.laneCount(rows: rows) == 2)
	}

	@Test("two branch tips forking from one commit converge into it")
	func forkWithoutMerge() {
		let rows = GitGraphLayout.layout(commits: [
			commit("A", parents: ["C"]),
			commit("B", parents: ["C"]),
			commit("C")
		])

		// A and B are unrelated tips, so B opens lane 1
		#expect(rows.map(\.column) == [0, 1, 0])
		#expect(rows[1].incomingColumns == [])
		#expect(rows[2].incomingColumns == [0, 1])
	}

	@Test("closed lanes are reused by later branch tips")
	func laneReuse() {
		// Tip A ends quickly at root R1; tip B appears later and should reuse lane…
		// Order: A (lane 0), B (lane 1), R1 closes lane 0, C is a new tip → lane 0
		let rows = GitGraphLayout.layout(commits: [
			commit("A", parents: ["R1"]),
			commit("B", parents: ["R2"]),
			commit("R1"),
			commit("C", parents: ["R2"]),
			commit("R2")
		])

		#expect(rows.map(\.column) == [0, 1, 0, 0, 0])

		// C reuses lane 0 freed by root R1, while lane 1 (waiting for R2) passes through
		#expect(rows[3].passThroughColumns == [1])

		// R2 is awaited by both lane 0 (from C) and lane 1 (from B)
		#expect(rows[4].incomingColumns == [0, 1])
	}

	@Test("merge second parent joins an existing lane instead of opening a new one")
	func mergeIntoExistingLane() {
		// B is already tracked in lane 1 when M merges it
		let rows = GitGraphLayout.layout(commits: [
			commit("T", parents: ["B"]),
			commit("M", parents: ["A", "B"]),
			commit("A", parents: ["C"]),
			commit("B", parents: ["C"]),
			commit("C")
		])

		// T occupies lane 0 waiting for B; M opens lane 1
		#expect(rows.map(\.column) == [0, 1, 1, 0, 0])

		// M's second parent B is already awaited by lane 0, so the edge joins it
		#expect(rows[1].outgoingColumns == [1, 0])
		#expect(GitGraphLayout.laneCount(rows: rows) == 2)
	}

	@Test("root commit with no parents closes its lane")
	func rootClosesLane() {
		let rows = GitGraphLayout.layout(commits: [
			commit("A", parents: ["R"]),
			commit("R")
		])

		#expect(rows[1].outgoingColumns == [])
		#expect(rows[1].passThroughColumns == [])
	}

	@Test("laneCount of empty rows is zero")
	func emptyLayout() {
		let rows = GitGraphLayout.layout(commits: [])
		#expect(rows.isEmpty)
		#expect(GitGraphLayout.laneCount(rows: rows) == 0)
	}
}
