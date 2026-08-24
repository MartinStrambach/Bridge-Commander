import Foundation
import Testing
@testable import Settings

@Suite("GitGraphColumnWidths")
struct GitGraphColumnWidthsTests {
	@Test("subscript reads back the stored width for every column")
	func subscriptReads() {
		let widths = GitGraphColumnWidths(graph: 200, author: 100, date: 110, hash: 60)

		#expect(widths[.graph] == 200)
		#expect(widths[.author] == 100)
		#expect(widths[.date] == 110)
		#expect(widths[.hash] == 60)
	}

	@Test("writes inside the allowed range are stored unchanged")
	func writesInRange() {
		var widths = GitGraphColumnWidths()
		widths[.graph] = 300
		#expect(widths.graph == 300)
	}

	@Test("writes are clamped to each column's allowed range")
	func writesAreClamped() {
		var widths = GitGraphColumnWidths()

		for column in GitGraphColumnWidths.Column.allCases {
			let range = GitGraphColumnWidths.range(for: column)

			widths[column] = range.lowerBound - 1000
			#expect(widths[column] == range.lowerBound)

			widths[column] = range.upperBound + 1000
			#expect(widths[column] == range.upperBound)
		}
	}

	@Test("survives a Codable round trip")
	func codableRoundTrip() throws {
		let widths = GitGraphColumnWidths(graph: 250, author: 90, date: 150, hash: 55)

		let data = try JSONEncoder().encode(widths)
		let decoded = try JSONDecoder().decode(GitGraphColumnWidths.self, from: data)

		#expect(decoded == widths)
	}
}
