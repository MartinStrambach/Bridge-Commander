import Testing

@testable import TerminalFeature

struct WaitingStateGateTests {
	@Test func holdsTheWaitingStateOnASingleActiveVerdict() {
		let gate = WaitingStateGate()
		let decision = gate.decide(verdict: .active, currentStatus: .waitingForInput)
		#expect(decision == .waitForConfirmation)
	}

	@Test func releasesTheWaitingStateOnTheSecondActiveVerdict() {
		let gate = WaitingStateGate()
		_ = gate.decide(verdict: .active, currentStatus: .waitingForInput)
		let decision = gate.decide(verdict: .active, currentStatus: .waitingForInput)
		#expect(decision == .report(.active))
	}

	@Test func aDisagreeingVerdictEndsTheStreak() {
		// The screen caught mid-repaint, then the settled screen with the prompt back on it.
		let gate = WaitingStateGate()
		_ = gate.decide(verdict: .active, currentStatus: .waitingForInput)
		#expect(gate.decide(verdict: .waitingForInput, currentStatus: .waitingForInput) == .report(.waitingForInput))
		// The next stray verdict starts from scratch rather than releasing the pane.
		#expect(gate.decide(verdict: .active, currentStatus: .waitingForInput) == .waitForConfirmation)
	}

	@Test func reportsWaitingImmediately() {
		let gate = WaitingStateGate()
		let decision = gate.decide(verdict: .waitingForInput, currentStatus: .active)
		#expect(decision == .report(.waitingForInput))
	}

	@Test func doesNotGateAPaneThatIsAlreadyActive() {
		let gate = WaitingStateGate()
		#expect(gate.decide(verdict: .active, currentStatus: .active) == .report(.active))
		#expect(gate.decide(verdict: .active, currentStatus: .active) == .report(.active))
	}

	@Test func countsConcurrentVerdictsWithoutLosingAny() async {
		// Every second agreeing verdict releases the pane, whatever order the calls arrive in. A
		// lost or double-counted increment shows up here as the wrong number of releases.
		let gate = WaitingStateGate()
		let verdicts = 1000
		let releases = await withTaskGroup(of: Int.self) { group in
			for _ in 0 ..< verdicts {
				group.addTask {
					gate.decide(verdict: .active, currentStatus: .waitingForInput) == .report(.active) ? 1 : 0
				}
			}
			return await group.reduce(0, +)
		}
		#expect(releases == verdicts / 2)
	}

	@Test func resetDropsAPartBuiltStreak() {
		let gate = WaitingStateGate()
		_ = gate.decide(verdict: .active, currentStatus: .waitingForInput)
		gate.reset()
		#expect(gate.decide(verdict: .active, currentStatus: .waitingForInput) == .waitForConfirmation)
	}
}
