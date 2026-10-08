import Foundation
import Testing
@testable import ActivityLog

struct ActivityLogTests {
	private func makeLog(maximumFileSize: UInt64 = 2_000_000) -> ActivityLog {
		ActivityLog(
			directory: FileManager.default.temporaryDirectory.appending(component: "ActivityLogTests-\(UUID())"),
			maximumFileSize: maximumFileSize
		)
	}

	@Test
	func detailsAreIndentedUnderTheirEntry() {
		let line = ActivityLog.line(
			date: Date(timeIntervalSince1970: 0),
			category: .git,
			message: "push origin",
			details: "error: failed\nhint: pull first"
		)

		let lines = line.split(separator: "\n")
		#expect(lines.count == 3)
		#expect(lines[0].hasSuffix("[git] push origin"))
		#expect(lines[1] == "    error: failed")
		#expect(lines[2] == "    hint: pull first")
	}

	@Test
	func homeFolderIsAbbreviated() {
		#expect(ActivityLog.abbreviatingHome("at /Users/jane/repo", home: "/Users/jane") == "at ~/repo")
	}

	@Test
	func exportHoldsRecordedEntriesAfterAHeader() async {
		let log = makeLog()
		log.record(.network, "GET https://example.com → 200 in 12 ms")

		let export = String(decoding: await log.exportData(), as: UTF8.self)
		#expect(export.contains("Exported "))
		#expect(export.contains("[network] GET https://example.com → 200 in 12 ms"))
	}

	@Test
	func aFullFileRotatesAndBothFilesAreExported() async {
		let log = makeLog(maximumFileSize: 100)
		log.record(.app, String(repeating: "a", count: 120))
		log.record(.app, "after rotation")

		let export = String(decoding: await log.exportData(), as: UTF8.self)
		#expect(FileManager.default.fileExists(atPath: log.previousFileURL.path))
		#expect(export.contains(String(repeating: "a", count: 120)))
		#expect(export.contains("after rotation"))
	}

	@Test
	func clearRemovesEverything() async {
		let log = makeLog(maximumFileSize: 100)
		log.record(.app, String(repeating: "a", count: 120))
		log.record(.app, "second")
		await log.clear()

		#expect(await log.size() == 0)
		log.record(.app, "after clear")
		#expect(String(decoding: await log.exportData(), as: UTF8.self).contains("after clear"))
	}

	@Test
	func cancellationIsNotRecorded() async {
		let log = makeLog()
		log.record(CancellationError(), context: "refresh")
		log.record(URLError(.cancelled), context: "refresh")

		#expect(await log.size() == 0)
	}

	@Test
	func flushWritesEverythingRecordedBeforeIt() throws {
		let log = makeLog()
		log.record(.app, "queued")
		log.flush()

		#expect(try String(contentsOf: log.fileURL, encoding: .utf8).contains("queued"))
	}

	/// Entries recorded from many threads at once all land, each on its own lines, none
	/// interleaved with another — rotating the file several times along the way.
	@Test
	func concurrentEntriesStayWholeAcrossRotations() async {
		let log = makeLog(maximumFileSize: 50_000)
		await withTaskGroup { group in
			for task in 0 ..< 8 {
				group.addTask {
					for entry in 0 ..< 250 {
						log.record(.git, "task \(task) entry \(entry)", details: "detail of \(task)-\(entry)")
					}
				}
			}
		}

		let lines = String(decoding: await log.exportData(), as: UTF8.self).split(separator: "\n")
		let entries = lines.filter { $0.contains("[git] task ") }
		// Two files of 50 KB hold the most recent entries; earlier ones rotated out.
		#expect(entries.count > 500)
		for (index, line) in lines.enumerated() where line.contains("[git] task ") {
			let id = line.split(separator: " ").suffix(3)
			#expect(lines[index + 1] == "    detail of \(id.first!)-\(id.last!)")
		}
	}

	@Test
	func errorsAreDescribedByDomainAndCodeOrByCase() {
		#expect(ActivityLog.describe(URLError(.notConnectedToInternet)).hasPrefix("NSURLErrorDomain -1009"))

		enum ServiceError: Error { case httpFailure(statusCode: Int) }
		#expect(ActivityLog.describe(ServiceError.httpFailure(statusCode: 401)).hasSuffix("httpFailure(statusCode: 401)"))
	}

	@Test
	func secretQueryItemsAndCredentialsAreRedacted() throws {
		let url = try #require(URL(string: "https://user:pw@example.com/api?private_token=abc&fields=id"))
		#expect(NetworkRequestLog.redacted(url) == "https://example.com/api?private_token=%3Credacted%3E&fields=id")
	}

	@Test
	func durationsReadAsMillisecondsOrSeconds() {
		#expect(Duration.milliseconds(840).activityLogDescription == "840 ms")
		#expect(Duration.milliseconds(2310).activityLogDescription == "2.31 s")
	}
}
