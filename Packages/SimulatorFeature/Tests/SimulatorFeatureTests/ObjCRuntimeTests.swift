import Foundation
import Testing
@testable import SimulatorFeature

struct ObjCRuntimeTests {
	@Test
	func anObjectiveCExceptionBecomesAThrownError() {
		// -[NSArray objectAtIndex:] out of bounds raises NSRangeException, as CoreSimulator's
		// assertions raise NSInternalInconsistencyException.
		#expect(throws: SimulatorError.self) {
			try ObjCRuntime.catchingException { NSArray().object(at: 1) as AnyObject }
		}
	}

	@Test
	func aCallThatDoesNotRaiseReturnsItsResult() throws {
		let array = NSArray(array: ["a"])
		let first = try ObjCRuntime.catchingException { ObjCRuntime.object(array, "firstObject") }
		#expect(first as? String == "a")
		let none = try ObjCRuntime.catchingException { ObjCRuntime.object(NSArray(), "firstObject") }
		#expect(none == nil)
	}
}
