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

	@Test("a conflict swaps only the success checkmark for a warning")
	func conflictIcon() {
		#expect(PipelineState.success.systemImageName(hasConflicts: true) == "exclamationmark.triangle.fill")
		#expect(PipelineState.success.systemImageName(hasConflicts: false) == "checkmark.circle.fill")
		#expect(PipelineState.failed.systemImageName(hasConflicts: true) == "xmark.octagon.fill")
		#expect(PipelineState.running.systemImageName(hasConflicts: true) == "arrow.triangle.2.circlepath")
	}

	@Test("a merge train pipeline in progress shows a tram; a finished one its result")
	func mergeTrainIcon() {
		#expect(PipelineState.running.systemImageName(hasConflicts: false, isMergeTrain: true) == "tram.fill")
		#expect(PipelineState.pending.systemImageName(hasConflicts: false, isMergeTrain: true) == "tram.fill")
		#expect(PipelineState.success.systemImageName(hasConflicts: false, isMergeTrain: true) == "checkmark.circle.fill")
		#expect(PipelineState.failed.systemImageName(hasConflicts: false, isMergeTrain: true) == "xmark.octagon.fill")
		#expect(PipelineState.running.systemImageName(hasConflicts: false) == "arrow.triangle.2.circlepath")
	}

	@Test("describes the MR's place on the merge train")
	func mergeTrainSummary() {
		#expect(MergeTrainStatus.onTrain(position: 2).summary == "#2 on the merge train")
		#expect(MergeTrainStatus.onTrain(position: nil).summary == "on the merge train")
		#expect(MergeTrainStatus.waitingToJoin.summary == "joins the merge train when checks pass")
	}
}
