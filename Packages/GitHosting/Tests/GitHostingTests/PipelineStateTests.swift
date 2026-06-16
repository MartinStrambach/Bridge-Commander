import Testing
@testable import GitHosting

@Suite("PipelineState")
struct PipelineStateTests {
	// MARK: - GitLab status string -> PipelineState

	@Test("maps the common GitLab statuses")
	func mapsCommonStatuses() {
		#expect(PipelineState(gitLabStatus: "success") == .success)
		#expect(PipelineState(gitLabStatus: "failed") == .failed)
		#expect(PipelineState(gitLabStatus: "running") == .running)
		#expect(PipelineState(gitLabStatus: "pending") == .pending)
		#expect(PipelineState(gitLabStatus: "canceled") == .canceled)
		#expect(PipelineState(gitLabStatus: "skipped") == .skipped)
		#expect(PipelineState(gitLabStatus: "manual") == .manual)
		#expect(PipelineState(gitLabStatus: "scheduled") == .scheduled)
		#expect(PipelineState(gitLabStatus: "created") == .created)
		#expect(PipelineState(gitLabStatus: "preparing") == .preparing)
	}

	@Test("maps snake_case multi-word status")
	func mapsSnakeCase() {
		#expect(PipelineState(gitLabStatus: "waiting_for_resource") == .waitingForResource)
	}

	@Test("returns nil for unknown status")
	func unknownReturnsNil() {
		#expect(PipelineState(gitLabStatus: "canceling") == nil)
		#expect(PipelineState(gitLabStatus: "") == nil)
		#expect(PipelineState(gitLabStatus: "bogus") == nil)
	}

	// MARK: - PipelineState -> SF Symbol name

	@Test("maps each state to an SF Symbol name")
	func mapsSystemImageName() {
		#expect(PipelineState.success.systemImageName == "checkmark.circle.fill")
		#expect(PipelineState.failed.systemImageName == "xmark.octagon.fill")
		#expect(PipelineState.running.systemImageName == "arrow.triangle.2.circlepath")
		#expect(PipelineState.pending.systemImageName == "clock")
		#expect(PipelineState.created.systemImageName == "clock")
		#expect(PipelineState.preparing.systemImageName == "clock")
		#expect(PipelineState.waitingForResource.systemImageName == "clock")
		#expect(PipelineState.scheduled.systemImageName == "clock")
		#expect(PipelineState.canceled.systemImageName == "stop.circle")
		#expect(PipelineState.skipped.systemImageName == "forward.end.circle")
		#expect(PipelineState.manual.systemImageName == "hand.tap")
	}
}
