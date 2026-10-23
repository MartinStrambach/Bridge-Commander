import Testing
@testable import SimulatorFeature

struct SimulatorDeviceAssignmentTests {
	@Test
	func theRepositorysOwnBootedDeviceWins() {
		let assignment = SimulatorDeviceAssignment(selections: ["/a": "A", "/b": "A"], lastSelected: "B")
		#expect(assignment.resolve(bootedIds: ["A", "B"], repositoryPath: "/a") == .device("A"))
	}

	@Test
	func aRepositoryWithoutADeviceDoesNotInheritAnotherWorktreesLastChoice() {
		let assignment = SimulatorDeviceAssignment(selections: ["/a": "A"], lastSelected: "A")
		#expect(assignment.storedDeviceId(repositoryPath: "/b") == nil)
		#expect(assignment.resolve(bootedIds: ["A", "B"], repositoryPath: "/b") == .device("B"))
	}

	@Test
	func aFreeLastChoiceIsPreferred() {
		let assignment = SimulatorDeviceAssignment(selections: ["/a": "A"], lastSelected: "C")
		#expect(assignment.storedDeviceId(repositoryPath: "/b") == "C")
		#expect(assignment.resolve(bootedIds: ["A", "B", "C"], repositoryPath: "/b") == .device("C"))
	}

	@Test
	func aShutDownOwnDeviceFallsBackToAFreeBootedOne() {
		let assignment = SimulatorDeviceAssignment(selections: ["/a": "A", "/b": "B"], lastSelected: "A")
		#expect(assignment.resolve(bootedIds: ["A", "C"], repositoryPath: "/b") == .device("C"))
	}

	@Test
	func whenEveryBootedDeviceIsTakenNoneIsTaken() {
		let assignment = SimulatorDeviceAssignment(
			selections: ["/a": "A", "/c": "A", "/b": "B", "/d": "D"],
			lastSelected: "A"
		)
		#expect(assignment.resolve(bootedIds: ["A"], repositoryPath: "/b") == .everyBootedDeviceTaken(["A": ["/a", "/c"]]))
	}

	@Test
	func noBootedDevice() {
		let assignment = SimulatorDeviceAssignment(selections: ["/a": "A"], lastSelected: "A")
		#expect(assignment.resolve(bootedIds: [], repositoryPath: "/a") == .noBootedDevice)
	}

	@Test
	func aClaudeOutsideTheAppPrefersAFreeDeviceButTakesAnyBootedOne() {
		let assignment = SimulatorDeviceAssignment(selections: ["/a": "A", "/b": "B"], lastSelected: "C")
		#expect(assignment.resolve(bootedIds: ["A", "B", "D"], repositoryPath: nil) == .device("D"))
		#expect(assignment.resolve(bootedIds: ["A", "B"], repositoryPath: nil) == .device("A"))
		#expect(assignment.resolve(bootedIds: ["A", "C"], repositoryPath: nil) == .device("C"))
	}
}
