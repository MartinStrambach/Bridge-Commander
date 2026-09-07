import Testing

@testable import GitCore

@Suite("GitCommitDiffHelper.parseNameStatus")
struct GitCommitDiffHelperTests {

	/// `git show --name-status -z` terminates every field with NUL, including the last.
	private func output(_ fields: String...) -> String {
		fields.map { $0 + "\0" }.joined()
	}

	@Test
	func parsesASingleModifiedFile() {
		let changes = GitCommitDiffHelper.parseNameStatus(output("M", "Sources/App.swift"))

		#expect(changes.count == 1)
		#expect(changes[0].path == "Sources/App.swift")
		#expect(changes[0].status == .modified)
		#expect(changes[0].oldPath == nil)
	}

	@Test
	func parsesEveryStatusInOneCommit() {
		let changes = GitCommitDiffHelper.parseNameStatus(
			output("A", "Added.swift", "M", "Modified.swift", "D", "Deleted.swift", "T", "Retyped.swift")
		)

		#expect(changes.map(\.path) == ["Added.swift", "Modified.swift", "Deleted.swift", "Retyped.swift"])
		#expect(changes.map(\.status) == [.added, .modified, .deleted, .typeChanged])
	}

	@Test
	func renameCarriesBothPathsAndDropsTheSimilarityScore() {
		let changes = GitCommitDiffHelper.parseNameStatus(output("R093", "Old/Name.swift", "New/Name.swift"))

		#expect(changes.count == 1)
		#expect(changes[0].status == .renamed)
		#expect(changes[0].path == "New/Name.swift")
		#expect(changes[0].oldPath == "Old/Name.swift")
	}

	@Test
	func copyCarriesBothPaths() {
		let changes = GitCommitDiffHelper.parseNameStatus(output("C100", "Source.swift", "Copy.swift"))

		#expect(changes.count == 1)
		#expect(changes[0].status == .copied)
		#expect(changes[0].path == "Copy.swift")
		#expect(changes[0].oldPath == "Source.swift")
	}

	/// A rename's two path fields must not be mistaken for the next record's status.
	@Test
	func parsesRecordsFollowingARename() {
		let changes = GitCommitDiffHelper.parseNameStatus(
			output("R093", "Old.swift", "New.swift", "M", "Other.swift")
		)

		#expect(changes.map(\.path) == ["New.swift", "Other.swift"])
		#expect(changes.map(\.status) == [.renamed, .modified])
	}

	@Test
	func emptyOutputYieldsNoChanges() {
		#expect(GitCommitDiffHelper.parseNameStatus("").isEmpty)
	}

	@Test
	func unknownStatusLettersAreSkipped() {
		// Git can report X (an internal bug) or B (a broken pair); neither is modelled.
		let changes = GitCommitDiffHelper.parseNameStatus(output("X", "Weird.swift", "M", "Real.swift"))

		#expect(changes.map(\.path) == ["Real.swift"])
	}

	@Test
	func truncatedTrailingRecordIsIgnored() {
		let changes = GitCommitDiffHelper.parseNameStatus(output("M", "First.swift", "M"))

		#expect(changes.map(\.path) == ["First.swift"])
	}

	@Test
	func pathsContainingSpacesSurviveIntact() {
		let changes = GitCommitDiffHelper.parseNameStatus(output("M", "Some Dir/My File.swift"))

		#expect(changes.map(\.path) == ["Some Dir/My File.swift"])
	}
}
