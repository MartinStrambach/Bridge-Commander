import Testing

@testable import GitCore

struct GitNumstatParserTests {

	@Test
	func parsesRegularEntries() {
		let output = "12\t3\tSources/App.swift\00\t7\tREADME.md\0"
		let stats = GitNumstatParser.parse(output)

		#expect(stats.count == 2)
		#expect(stats["Sources/App.swift"] == GitLineStats(added: 12, removed: 3))
		#expect(stats["README.md"] == GitLineStats(added: 0, removed: 7))
	}

	@Test
	func parsesRenameEntryUnderNewPath() {
		let output = "5\t2\t\0Old/Name.swift\0New/Name.swift\0"
		let stats = GitNumstatParser.parse(output)

		#expect(stats.count == 1)
		#expect(stats["New/Name.swift"] == GitLineStats(added: 5, removed: 2))
		#expect(stats["Old/Name.swift"] == nil)
	}

	@Test
	func skipsBinaryEntries() {
		let output = "-\t-\tAssets/logo.png\04\t1\tSources/App.swift\0"
		let stats = GitNumstatParser.parse(output)

		#expect(stats.count == 1)
		#expect(stats["Assets/logo.png"] == nil)
		#expect(stats["Sources/App.swift"] == GitLineStats(added: 4, removed: 1))
	}

	@Test
	func skipsBinaryRenameEntryWithoutMisreadingFollowingRecords() {
		let output = "-\t-\t\0Old/logo.png\0New/logo.png\01\t1\tSources/App.swift\0"
		let stats = GitNumstatParser.parse(output)

		#expect(stats.count == 1)
		#expect(stats["Sources/App.swift"] == GitLineStats(added: 1, removed: 1))
	}

	@Test
	func handlesPathsWithSpacesAndTabsAfterSecondTab() {
		let output = "2\t0\tDocs/My File Name.md\0"
		let stats = GitNumstatParser.parse(output)

		#expect(stats["Docs/My File Name.md"] == GitLineStats(added: 2, removed: 0))
	}

	@Test
	func emptyOutputYieldsNoStats() {
		#expect(GitNumstatParser.parse("").isEmpty)
	}
}
