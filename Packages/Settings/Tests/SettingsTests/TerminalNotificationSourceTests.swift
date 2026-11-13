import Testing

@testable import Settings

struct TerminalNotificationSourceTests {
	@Test("automatic posts a program's status reports, and its own notifications only when it reports none")
	func automaticPostsOneChannelPerProgram() {
		let source = TerminalNotificationSource.automatic
		#expect(source.postsStatusReports)
		#expect(!source.postsProgramNotification(fromStatusReportingProgram: true))
		#expect(source.postsProgramNotification(fromStatusReportingProgram: false))
	}

	@Test("status reports only never posts a program's own notifications")
	func statusReportsOnly() {
		let source = TerminalNotificationSource.statusReports
		#expect(source.postsStatusReports)
		#expect(!source.postsProgramNotification(fromStatusReportingProgram: true))
		#expect(!source.postsProgramNotification(fromStatusReportingProgram: false))
	}

	@Test("program notifications only never posts a status report")
	func programNotificationsOnly() {
		let source = TerminalNotificationSource.programNotifications
		#expect(!source.postsStatusReports)
		#expect(source.postsProgramNotification(fromStatusReportingProgram: true))
		#expect(source.postsProgramNotification(fromStatusReportingProgram: false))
	}
}
