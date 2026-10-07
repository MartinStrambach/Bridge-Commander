import Foundation
import Testing
@testable import SimulatorFeature

/// Minimal reports shaped like real ones from an iOS 27 simulator on macOS 27 (most fields and
/// all but a few frames and images left out).
enum CrashFixtures {
	static let udid = "BFB0C060-7F42-4F7E-BD90-E985305981CB"
	static let otherUdid = "2C7993D8-0DB1-405F-86E7-1B22B932236F"
	static let appPath = "/Users/USER/Library/Developer/CoreSimulator/Devices/\(udid)/data/Containers/Bundle/Application/46D4A3C2-CF6F-4C13-BA92-FFF85E7B4628/CrashDemo.app/CrashDemo"

	/// An uncaught `NSRangeException`: SIGABRT, with the throw site in `lastExceptionBacktrace`.
	static let uncaughtException = """
	{"app_name":"CrashDemo","timestamp":"2026-10-07 19:31:28.00 +0200","app_version":"1.2","build_version":"34","platform":7,"bundleID":"com.example.CrashDemo","bug_type":"309","os_version":"macOS 27.0.1 (26A434)","name":"CrashDemo","incident_id":"0F6D3E39-6F4C-4B40-9C55-2A3F2B1C5E11"}
	{
	  "pid" : 99482,
	  "procName" : "CrashDemo",
	  "procPath" : "\(appPath)",
	  "procLaunch" : "2026-10-07 19:31:27.1201 +0200",
	  "captureTime" : "2026-10-07 19:31:28.2520 +0200",
	  "bundleInfo" : {"CFBundleShortVersionString":"1.2","CFBundleVersion":"34","CFBundleIdentifier":"com.example.CrashDemo"},
	  "parentProc" : "launchd_sim",
	  "coalitionName" : "com.apple.CoreSimulator.SimDevice.\(udid)",
	  "responsibleProc" : "SimulatorTrampoline",
	  "exception" : {"codes":"0x0000000000000000, 0x0000000000000000","rawCodes":[0,0],"type":"EXC_CRASH","signal":"SIGABRT"},
	  "termination" : {"flags":0,"code":6,"namespace":"SIGNAL","indicator":"Abort trap: 6","byProc":"CrashDemo","byPid":99482},
	  "lastExceptionBacktrace" : [
	    {"imageOffset":1302296,"symbol":"__exceptionPreprocess","symbolLocation":160,"imageIndex":2},
	    {"imageOffset":170316,"symbol":"objc_exception_throw","symbolLocation":72,"imageIndex":1},
	    {"imageOffset":8176,"symbol":"crash(_:)","symbolLocation":256,"imageIndex":0}
	  ],
	  "faultingThread" : 0,
	  "threads" : [
	    {"triggered":true,"id":10200589,"queue":"com.apple.main-thread","frames":[
	      {"imageOffset":34976,"symbol":"__pthread_kill","symbolLocation":8,"imageIndex":3},
	      {"imageOffset":481792,"symbol":"abort","symbolLocation":116,"imageIndex":4}
	    ]},
	    {"id":10200590,"frames":[]}
	  ],
	  "usedImages" : [
	    {"source":"P","arch":"arm64","base":4364288000,"size":32768,"path":"\(appPath)","name":"CrashDemo","CFBundleIdentifier":"com.example.CrashDemo"},
	    {"source":"P","arch":"arm64","base":7516192768,"size":200000,"path":"/usr/lib/libobjc.A.dylib","name":"libobjc.A.dylib"},
	    {"source":"P","arch":"arm64","base":7520000000,"size":4000000,"path":"/Volumes/VOLUME/*/CoreFoundation.framework/CoreFoundation","name":"CoreFoundation"},
	    {"source":"P","arch":"arm64","base":7530000000,"size":100000,"path":"/usr/lib/system/libsystem_kernel.dylib","name":"libsystem_kernel.dylib"},
	    {"source":"P","arch":"arm64","base":7540000000,"size":600000,"path":"/usr/lib/system/libsystem_c.dylib","name":"libsystem_c.dylib"}
	  ]
	}
	"""

	/// A null-pointer write: SIGSEGV with a subtype, source locations, an unsymbolicated frame.
	static let segfault = """
	{"app_name":"CrashDemo","timestamp":"2026-10-07 19:32:14.00 +0200","app_version":"1.2","build_version":"34","platform":7,"bundleID":"com.example.CrashDemo","bug_type":"309","name":"CrashDemo"}
	{
	  "pid" : 99908,
	  "procPath" : "\(appPath)",
	  "captureTime" : "2026-10-07 19:32:10.9146 +0200",
	  "coalitionName" : "com.apple.CoreSimulator.SimDevice.\(udid)",
	  "exception" : {"codes":"0x0000000000000001, 0x0000000000000010","rawCodes":[1,16],"type":"EXC_BAD_ACCESS","signal":"SIGSEGV","subtype":"KERN_INVALID_ADDRESS at 0x0000000000000010"},
	  "termination" : {"flags":0,"code":11,"namespace":"SIGNAL","indicator":"Segmentation fault: 11","byProc":"exc handler","byPid":99908},
	  "faultingThread" : 0,
	  "threads" : [
	    {"triggered":true,"queue":"com.apple.main-thread","frames":[
	      {"imageOffset":8700,"sourceLine":31,"sourceFile":"main.swift","symbol":"crash(_:)","symbolLocation":780,"imageIndex":0},
	      {"imageOffset":7836,"sourceFile":"/<compiler-generated>","symbol":"thunk for @escaping @callee_guaranteed () -> ()","symbolLocation":48,"imageIndex":0},
	      {"imageOffset":4096,"imageIndex":1}
	    ]}
	  ],
	  "usedImages" : [
	    {"base":4364288000,"path":"\(appPath)","name":"CrashDemo"},
	    {"base":4400000000,"path":"/usr/lib/libunknown.dylib","name":"libunknown.dylib"}
	  ]
	}
	"""

	/// One of the runtime's own processes, whose path is anonymised and carries no UDID.
	static let systemProcess = """
	{"app_name":"PosterBoard","timestamp":"2026-10-07 19:23:07.00 +0200","app_version":"1.0","build_version":"1","platform":7,"bundleID":"com.apple.PosterBoard","bug_type":"309","name":"PosterBoard"}
	{
	  "pid" : 61889,
	  "procPath" : "/Volumes/VOLUME/*/PosterBoard.app/PosterBoard",
	  "captureTime" : "2026-10-07 19:23:06.8377 +0200",
	  "coalitionName" : "com.apple.CoreSimulator.SimDevice.\(udid)",
	  "exception" : {"codes":"0x0000000000000001, 0x00000001e3649210","rawCodes":[1,8109986320],"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
	  "termination" : {"flags":0,"code":5,"namespace":"SIGNAL","indicator":"Trace/BPT trap: 5","byProc":"exc handler","byPid":93494},
	  "faultingThread" : 0,
	  "threads" : [{"frames":[{"imageOffset":24592,"symbol":"-[PRPosterDescriptor _initWithPath:]","symbolLocation":312,"imageIndex":0}]}],
	  "usedImages" : [{"base":4366860288,"path":"/Volumes/VOLUME/*/PosterBoard.app/PosterBoard","name":"PosterBoard"}]
	}
	"""

	/// A Mac process: no simulator coalition. Its `asi` is what simulator reports lack.
	static let macCrash = """
	{"app_name":"ports","timestamp":"2026-10-07 19:35:39.00 +0200","bug_type":"309","platform":1,"name":"ports"}
	{
	  "procPath" : "/usr/local/bin/ports",
	  "captureTime" : "2026-10-07 19:35:38.1000 +0200",
	  "coalitionName" : "com.apple.Terminal",
	  "exception" : {"type":"EXC_CRASH","signal":"SIGABRT","codes":"0x0, 0x0"},
	  "asi" : {"libsystem_c.dylib":["abort() called"]},
	  "faultingThread" : 0,
	  "threads" : [{"frames":[]}],
	  "usedImages" : []
	}
	"""

	/// Another simulator, same app.
	static var otherDevice: String {
		uncaughtException
			.replacingOccurrences(of: udid, with: otherUdid)
			.replacingOccurrences(of: "19:31:28", with: "19:33:00")
	}

	static func date(_ text: String) -> Date {
		SimulatorCrashReport.date(text)!
	}
}

struct SimulatorCrashReportTests {
	@Test
	func parsesAnUncaughtExceptionFromAnInstalledApp() throws {
		let report = try #require(SimulatorCrashReport.parse(fileName: "CrashDemo-1.ips", contents: CrashFixtures.uncaughtException))
		#expect(report.appName == "CrashDemo")
		#expect(report.bundleID == "com.example.CrashDemo")
		#expect(report.appVersion == "1.2")
		#expect(report.buildVersion == "34")
		#expect(report.deviceUDID == CrashFixtures.udid)
		#expect(report.isInstalledApp)
		#expect(report.pid == 99482)
		#expect(report.timeText == "2026-10-07 19:31:28 +0200")
		#expect(report.time == CrashFixtures.date("2026-10-07 19:31:28.2520 +0200"))
		#expect(report.exceptionType == "EXC_CRASH")
		#expect(report.exceptionSignal == "SIGABRT")
		#expect(report.termination == "SIGNAL 6, Abort trap: 6, by CrashDemo")
		#expect(report.mainImage == "CrashDemo")
		#expect(report.lastExceptionBacktrace.map(\.symbol) == ["__exceptionPreprocess", "objc_exception_throw", "crash(_:)"])
		#expect(report.lastExceptionBacktrace.last?.image == "CrashDemo")
		#expect(report.lastExceptionBacktrace.last?.address == 4364288000 + 8176)
		#expect(report.crashedThread?.index == 0)
		#expect(report.crashedThread?.queue == "com.apple.main-thread")
		#expect(report.crashedThread?.frames.map(\.image) == ["libsystem_kernel.dylib", "libsystem_c.dylib"])
	}

	@Test
	func identifiesTheDeviceByCoalitionOrPath() {
		#expect(SimulatorCrashReport.deviceUDID(coalitionName: "com.apple.CoreSimulator.SimDevice.\(CrashFixtures.udid.lowercased())", procPath: nil) == CrashFixtures.udid)
		#expect(SimulatorCrashReport.deviceUDID(coalitionName: "com.apple.Terminal", procPath: CrashFixtures.appPath) == CrashFixtures.udid)
		#expect(SimulatorCrashReport.deviceUDID(coalitionName: "com.apple.Terminal", procPath: "/Applications/Safari.app/Contents/MacOS/Safari") == nil)

		let system = SimulatorCrashReport.parse(fileName: "PosterBoard.ips", contents: CrashFixtures.systemProcess)
		#expect(system?.deviceUDID == CrashFixtures.udid)
		#expect(system?.isInstalledApp == false)
		#expect(SimulatorCrashReport.parse(fileName: "ports.ips", contents: CrashFixtures.macCrash)?.isSimulator == false)
	}

	@Test
	func onlyCrashReportsParse() {
		let stackshot = CrashFixtures.segfault.replacingOccurrences(of: "\"bug_type\":\"309\"", with: "\"bug_type\":\"288\"")
		#expect(SimulatorCrashReport.parse(fileName: "a.ips", contents: stackshot) == nil)
		#expect(SimulatorCrashReport.parse(fileName: "a.ips", contents: "Process: CrashDemo [123]\nPath: /x") == nil)
		#expect(SimulatorCrashReport.parse(fileName: "a.ips", contents: "") == nil)
	}

	@Test
	func summarisesAReport() throws {
		let report = try #require(SimulatorCrashReport.parse(fileName: "CrashDemo-2.ips", contents: CrashFixtures.segfault))
		#expect(SimulatorCrashReportFormatter.summary(report, logMessages: ["(libswiftCore.dylib) main.swift:28: Fatal error: Boom"]) == """
		CrashDemo 1.2 (34) — com.example.CrashDemo
		Crashed 2026-10-07 19:32:10 +0200, pid 99908
		Simulator: \(CrashFixtures.udid)
		Path: \(CrashFixtures.appPath)
		Exception: EXC_BAD_ACCESS (SIGSEGV), KERN_INVALID_ADDRESS at 0x0000000000000010
		Codes: 0x0000000000000001, 0x0000000000000010
		Termination: SIGNAL 11, Segmentation fault: 11, by exc handler

		From the simulator's log at the time of the crash:
		  (libswiftCore.dylib) main.swift:28: Fatal error: Boom

		Crashed thread 0 (com.apple.main-thread):
		  0  CrashDemo  crash(_:) + 780 (main.swift:31)
		  1  CrashDemo  thunk for @escaping @callee_guaranteed () -> () + 48
		  2  libunknown.dylib  0x\(String(4400000000 + 4096, radix: 16))
		""")
	}

	@Test
	func summaryPointsToTheLogWhenItHasNoMessage() throws {
		let report = try #require(SimulatorCrashReport.parse(fileName: "CrashDemo-1.ips", contents: CrashFixtures.uncaughtException))
		let summary = SimulatorCrashReportFormatter.summary(report)
		#expect(summary.contains("xcrun simctl spawn \(CrashFixtures.udid) log show --style compact --start '2026-10-07 17:30:28+0000' --end '2026-10-07 17:31:33+0000' --predicate 'processID == 99482'"))
		#expect(summary.contains("""
		Last exception backtrace:
		  0  CoreFoundation  __exceptionPreprocess + 160
		  1  libobjc.A.dylib  objc_exception_throw + 72
		  2  CrashDemo  crash(_:) + 256
		"""))
		#expect(summary.contains("Crashed 2026-10-07 19:31:28 +0200, launched 2026-10-07 19:31:27 +0200, pid 99482"))

		let mac = try #require(SimulatorCrashReport.parse(fileName: "ports.ips", contents: CrashFixtures.macCrash))
		#expect(SimulatorCrashReportFormatter.summary(mac).contains("Application-specific information:\n  libsystem_c.dylib: abort() called"))
	}

	@Test
	func summariesAreCapped() throws {
		var report = try #require(SimulatorCrashReport.parse(fileName: "CrashDemo-2.ips", contents: CrashFixtures.segfault))
		let long = SimulatorCrashReport.Frame(image: "CrashDemo", symbol: String(repeating: "generic specialization ", count: 40), symbolOffset: 4)
		report.crashedThread?.frames = Array(repeating: long, count: 100)
		report.lastExceptionBacktrace = Array(repeating: long, count: 100)
		let summary = SimulatorCrashReportFormatter.summary(report, logMessages: Array(repeating: String(repeating: "x", count: 2000), count: 4))
		#expect(summary.utf8.count <= SimulatorCrashReportFormatter.maxBytes)
		#expect(summary.hasSuffix("… (truncated)"))
	}

	@Test
	func listLineSaysWhatWentWrongAndWhere() throws {
		let now = CrashFixtures.date("2026-10-07 19:40:00 +0200")
		let exception = try #require(SimulatorCrashReport.parse(fileName: "CrashDemo-1.ips", contents: CrashFixtures.uncaughtException))
		#expect(SimulatorCrashReportFormatter.listLine(exception, now: now)
			== "2026-10-07 19:31:28 +0200 (8 min ago)  CrashDemo 1.2 (34) — com.example.CrashDemo  EXC_CRASH (SIGABRT): uncaught exception; in crash(_:) — CrashDemo-1.ips")
		let segfault = try #require(SimulatorCrashReport.parse(fileName: "CrashDemo-2.ips", contents: CrashFixtures.segfault))
		#expect(SimulatorCrashReportFormatter.listLine(segfault, now: now).contains("EXC_BAD_ACCESS (SIGSEGV): KERN_INVALID_ADDRESS at 0x0000000000000010; in crash(_:)"))
	}
}

struct SimulatorCrashReportsTests {
	/// Fixture files in memory, with what the tools asked of them.
	final class FakeSource: SimulatorCrashReportSource, @unchecked Sendable {
		var files: [String: (contents: String, modified: Date)]
		var logMessages: [String] = []
		private(set) var logQueries: [String] = []

		init(_ files: [String: (contents: String, modified: Date)] = [:]) {
			self.files = files
		}

		func reportFiles() async throws -> [CrashReportFile] {
			files.map { CrashReportFile(name: $0.key, modified: $0.value.modified) }
		}

		func contents(ofReport name: String) async throws -> String {
			guard let file = files[name] else {
				throw SimulatorCrashReports.Failure.notFound(name)
			}
			return file.contents
		}

		func crashMessages(udid: String, pid: Int, at time: Date) async -> [String] {
			logQueries.append("\(udid) \(pid)")
			return logMessages
		}
	}

	static let now = CrashFixtures.date("2026-10-07 19:40:00 +0200")

	static func source() -> FakeSource {
		let recent = now.addingTimeInterval(-60)
		return FakeSource([
			"CrashDemo-2026-10-07-193128.ips": (CrashFixtures.uncaughtException, recent),
			"CrashDemo-2026-10-07-193214.ips": (CrashFixtures.segfault, recent),
			"PosterBoard-2026-10-07-192307.ips": (CrashFixtures.systemProcess, recent),
			"CrashDemo-2026-10-07-193300.ips": (CrashFixtures.otherDevice, recent),
			"ports-2026-10-07-193539.ips": (CrashFixtures.macCrash, recent),
			// Rewritten lately, but the crash it records is a week old.
			"PosterBoard-2026-10-01-234536.ips": (
				CrashFixtures.systemProcess.replacingOccurrences(of: "2026-10-07 19:23", with: "2026-10-01 23:45"),
				recent
			),
			"CrashDemo-2026-10-06-100000.ips": (CrashFixtures.segfault, now.addingTimeInterval(-86400)),
		])
	}

	@Test
	func listsTheDevicesAppCrashesNewestFirst() async throws {
		let text = try await SimulatorCrashReports.list(
			SimulatorCrashReports.ListRequest(udid: CrashFixtures.udid.lowercased(), deviceName: "iPhone 17"),
			source: Self.source(),
			now: Self.now
		)
		let lines = text.split(separator: "\n").map(String.init)
		#expect(lines.first == "2 crashes on iPhone 17 in the last 60 minutes, newest first:")
		#expect(lines[1].hasSuffix("— CrashDemo-2026-10-07-193214.ips"))
		#expect(lines[2].hasSuffix("— CrashDemo-2026-10-07-193128.ips"))
		#expect(lines.last == "1 crash of the simulator's own processes not shown; include_system lists them.")
	}

	@Test
	func listFiltersByAppTimeAndLimit() async throws {
		let all = try await SimulatorCrashReports.list(
			SimulatorCrashReports.ListRequest(sinceMinutes: 30, limit: 1, includeSystem: true),
			source: Self.source(),
			now: Self.now
		)
		#expect(all.hasPrefix("4 crashes on any simulator in the last 30 minutes, newest first (showing 1):\n"))
		#expect(all.contains("CrashDemo-2026-10-07-193300.ips"))

		let posterBoard = try await SimulatorCrashReports.list(
			SimulatorCrashReports.ListRequest(udid: CrashFixtures.udid, bundleID: "com.apple.PosterBoard", sinceMinutes: 7 * 24 * 60),
			source: Self.source(),
			now: Self.now
		)
		#expect(posterBoard.hasPrefix("2 crashes com.apple.PosterBoard on \(CrashFixtures.udid) in the last 168 hours"))

		let none = try await SimulatorCrashReports.list(
			SimulatorCrashReports.ListRequest(udid: CrashFixtures.udid, sinceMinutes: 5),
			source: Self.source(),
			now: Self.now
		)
		#expect(none == "No crashes on \(CrashFixtures.udid) in the last 5 minutes.")
	}

	@Test
	func reportAsksTheLogForTheMessageReportsLeaveOut() async throws {
		let source = Self.source()
		source.logMessages = ["(CoreFoundation) *** Terminating app due to uncaught exception 'NSRangeException'"]
		let text = try await SimulatorCrashReports.report(named: " CrashDemo-2026-10-07-193128.ips ", source: source)
		#expect(text.contains("From the simulator's log at the time of the crash:\n  (CoreFoundation) *** Terminating app"))
		#expect(source.logQueries == ["\(CrashFixtures.udid) 99482"])

		let mac = try await SimulatorCrashReports.report(named: "ports-2026-10-07-193539.ips", source: source)
		#expect(mac.contains("abort() called"))
		#expect(source.logQueries.count == 1)
	}

	@Test
	func reportRefusesAnythingButAReportName() async throws {
		for name in ["../secret.ips", "/etc/passwd", "Retired/a.ips", ".hidden.ips", "notes.txt", "", "a\\b.ips", "a:b.ips"] {
			#expect(throws: SimulatorCrashReports.Failure.self) {
				try SimulatorCrashReports.validatedName(name)
			}
		}
		#expect(try SimulatorCrashReports.validatedName("CrashDemo-2026-10-07-193214.000.ips") == "CrashDemo-2026-10-07-193214.000.ips")
		await #expect(throws: SimulatorCrashReports.Failure.notFound("Missing.ips")) {
			try await SimulatorCrashReports.report(named: "Missing.ips", source: Self.source())
		}
	}

	@Test
	func readsCrashMessagesFromTheLog() {
		let output = """
		Filtering the log data using "processID == 99482"
		Timestamp               Ty Process[PID:TID]
		2026-10-07 19:31:28.194 Df CrashDemo[99482:9ada0d] (CoreFoundation) *** Terminating app due to uncaught exception 'NSRangeException', reason: 'index 5 beyond bounds'
		*** First throw call stack:
		(
			0   CoreFoundation                      0x00000001c0287f24 __exceptionPreprocess + 172
		)
		2026-10-07 19:31:28.194 Df CrashDemo[99482:9ada0d] (CoreFoundation) *** Terminating app due to uncaught exception 'NSRangeException', reason: 'index 5 beyond bounds'
		"""
		#expect(SimulatorCrashReports.crashMessages(fromLog: output) == [
			"(CoreFoundation) *** Terminating app due to uncaught exception 'NSRangeException', reason: 'index 5 beyond bounds'",
		])
	}

	@Test
	func logQueryCoversTheMinuteBeforeTheCrash() {
		let arguments = SimulatorCrashReports.logArguments(pid: 42, at: CrashFixtures.date("2026-10-07 19:31:28 +0200"))
		#expect(Array(arguments.prefix(7)) == ["show", "--style", "compact", "--start", "2026-10-07 17:30:28+0000", "--end", "2026-10-07 17:31:33+0000"])
		#expect(arguments.last?.hasPrefix("processID == 42 AND (eventMessage CONTAINS \"Terminating app") == true)
	}
}
