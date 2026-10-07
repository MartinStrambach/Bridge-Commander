import Testing
@testable import SimulatorFeature

struct SimulatorKeyboardMapTests {
	@Test
	func lettersDigitsAndShiftedSymbols() {
		#expect(SimulatorKeyboardMap.keyStroke(for: "a") == SimulatorKeyStroke(usage: 0x04))
		#expect(SimulatorKeyboardMap.keyStroke(for: "Z") == SimulatorKeyStroke(usage: 0x1D, modifiers: [0xE1]))
		#expect(SimulatorKeyboardMap.keyStroke(for: "1") == SimulatorKeyStroke(usage: 0x1E))
		#expect(SimulatorKeyboardMap.keyStroke(for: "0") == SimulatorKeyStroke(usage: 0x27))
		#expect(SimulatorKeyboardMap.keyStroke(for: "@") == SimulatorKeyStroke(usage: 0x1F, modifiers: [0xE1]))
		#expect(SimulatorKeyboardMap.keyStroke(for: "\n") == SimulatorKeyStroke(usage: 0x28))
		#expect(SimulatorKeyboardMap.keyStroke(for: "\r\n") == SimulatorKeyStroke(usage: 0x28))
	}

	@Test
	func textWithUntypeableCharactersFailsNamingThem() {
		let result = SimulatorKeyboardMap.keyStrokes(for: "héllo é")
		guard case let .failure(error) = result else {
			Issue.record("expected a failure")
			return
		}
		#expect(error == .untypeableText("\"é\""))
	}

	@Test
	func typeableTextMapsEveryCharacter() throws {
		let strokes = try SimulatorKeyboardMap.keyStrokes(for: "Hi!").get()
		#expect(strokes.map(\.usage) == [0x0B, 0x0C, 0x1E])
	}

	@Test
	func namedKeysWithModifiers() {
		#expect(SimulatorKeyboardMap.keyStroke(named: "return") == SimulatorKeyStroke(usage: 0x28))
		#expect(SimulatorKeyboardMap.keyStroke(named: "Cmd+V") == SimulatorKeyStroke(usage: 0x19, modifiers: [0xE3]))
		#expect(SimulatorKeyboardMap.keyStroke(named: "shift+tab") == SimulatorKeyStroke(usage: 0x2B, modifiers: [0xE1]))
		#expect(SimulatorKeyboardMap.keyStroke(named: "cmd++") == SimulatorKeyStroke(usage: 0x2E, modifiers: [0xE1, 0xE3]))
		#expect(SimulatorKeyboardMap.keyStroke(named: "hyper+a") == nil)
		#expect(SimulatorKeyboardMap.keyStroke(named: "nosuchkey") == nil)
	}
}
