import Foundation
import Testing
@testable import SimulatorFeature

struct ClaudeCodeRegistrationTests {
	@Test
	func configurationDefersToThePaneEnvironment() throws {
		let configuration = try JSONDecoder().decode(JSONValue.self, from: Data(ClaudeCodeRegistration.configuration.utf8))
		#expect(configuration["type"] == "http")
		#expect(configuration["url"] == "${BC_SIMULATOR_MCP_URL:-http://127.0.0.1:47615/mcp}")
		#expect(configuration["headers"]?["X-Bridge-Commander-Session"] == "${BC_TERMINAL_SESSION_ID:-none}")
	}

	@Test
	func registrationIsReadFromTheUserScopeServers() {
		let registered = Data(#"{"mcpServers":{"bridge-commander-simulator":{"type":"http"}},"projects":{}}"#.utf8)
		let projectOnly = Data(#"{"projects":{"/x":{"mcpServers":{"bridge-commander-simulator":{}}}}}"#.utf8)
		#expect(ClaudeCodeRegistration.isRegistered(inConfig: registered))
		#expect(!ClaudeCodeRegistration.isRegistered(inConfig: projectOnly))
		#expect(!ClaudeCodeRegistration.isRegistered(inConfig: Data("not json".utf8)))
	}
}
