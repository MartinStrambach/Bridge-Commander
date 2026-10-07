import Foundation
import ProcessExecution

/// Adds the simulator MCP server to Claude Code's user-scope configuration, once.
///
/// The entry is static, and works in every pane because Claude Code expands environment variables
/// in an MCP server's `url` and `headers` when it loads them:
///
/// - `url` is `${BC_SIMULATOR_MCP_URL:-<release URL>}`. Panes get the running app's own URL (the
///   debug build's port differs); a `claude` started elsewhere falls back to the release app's.
/// - The session header carries `${BC_TERMINAL_SESSION_ID}`, so the server knows which tab a call
///   came from and opens the pane beside it.
///
/// A `claude` started outside the app while it is not running lists the server as failed to
/// connect, and carries on without it.
public nonisolated enum ClaudeCodeRegistration {
	public static let serverName = SimulatorMCPHandler.serverName

	static var configuration: String {
		let fallback = "http://127.0.0.1:\(SimulatorMCPServer.releasePort)\(SimulatorMCPHandler.path)"
		let json: JSONValue = [
			"type": "http",
			"url": .string("${\(SimulatorMCPServer.urlEnvironmentVariable):-\(fallback)}"),
			"headers": [
				"X-Bridge-Commander-Session": .string("${\(SimulatorMCPServer.sessionEnvironmentVariable):-none}"),
			],
		]
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
		return (try? encoder.encode(json)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
	}

	/// Claude Code's global config: `~/.claude.json`, or `.claude.json` inside `CLAUDE_CONFIG_DIR`
	/// when that is set (read from this app's environment, like `ClaudeSession` does).
	static var configFile: URL {
		if let directory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !directory.isEmpty {
			return URL(fileURLWithPath: directory).appending(component: ".claude.json")
		}
		return FileManager.default.homeDirectoryForCurrentUser.appending(component: ".claude.json")
	}

	/// Whether the user-scope config already has the server.
	public static func isRegistered() -> Bool {
		guard let data = try? Data(contentsOf: configFile) else {
			return false
		}
		return isRegistered(inConfig: data)
	}

	static func isRegistered(inConfig data: Data) -> Bool {
		guard let config = try? JSONDecoder().decode(JSONValue.self, from: data) else {
			return false
		}
		return config["mcpServers"]?[serverName] != nil
	}

	/// Runs `claude mcp add-json --scope user` in a login shell, where `claude` is on the PATH the
	/// user's own terminals have.
	public static func register() async throws {
		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/bin/zsh"),
			arguments: [
				"-lc",
				#"claude mcp add-json --scope user "$1" "$2""#,
				"zsh",
				serverName,
				configuration,
			],
			environment: EnvironmentHelper.setupEnvironment()
		)
		guard result.success else {
			let output = (result.errorString + result.outputString).trimmingCharacters(in: .whitespacesAndNewlines)
			throw SimulatorError.commandFailed(output.isEmpty ? "claude mcp add-json failed (exit \(result.exitCode))" : output)
		}
	}
}
