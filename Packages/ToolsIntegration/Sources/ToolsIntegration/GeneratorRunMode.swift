import Foundation
import ProcessExecution

// MARK: - Generator Run Mode

/// How a project generator's CLI (Tuist, XcodeGen) is started: through `mise exec`, which picks
/// the version the repository pins, or straight from `PATH`.
public nonisolated enum GeneratorRunMode: String, Equatable, CaseIterable, Codable, Sendable {
	case mise
	case native

	public var displayName: String {
		switch self {
		case .mise:
			"mise"
		case .native:
			"Native"
		}
	}

	/// The shell command that runs `tool` with `arguments` in this mode.
	func command(_ tool: String, arguments: String, misePath: String) -> String {
		switch self {
		case .mise:
			"\(misePath) exec -- \(tool) \(arguments)"
		case .native:
			"\(tool) \(arguments)"
		}
	}
}

// MARK: - Generator Shell

nonisolated enum GeneratorShell {
	/// Runs `command` in an interactive zsh at `path`, so the user's shell setup (PATH, mise
	/// activation) applies as in a terminal.
	/// - Returns: stdout and stderr joined on success; on failure an error whose description is
	///   stderr, or the exit code when stderr is empty
	static func run(_ command: String, at path: String, errorDomain: String) async -> Result<String, Error> {
		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/bin/zsh"),
			arguments: ["-i", "-c", command],
			currentDirectory: URL(fileURLWithPath: path),
			environment: EnvironmentHelper.setupEnvironment()
		)

		if result.success {
			let combined = [result.outputString, result.errorString]
				.filter { !$0.isEmpty }
				.joined(separator: "\n")
			return .success(combined.trimmingCharacters(in: .whitespacesAndNewlines))
		}

		let errorMessage = result.errorString.isEmpty
			? "Command failed with exit code \(result.exitCode)"
			: result.errorString
		return .failure(NSError(
			domain: errorDomain,
			code: Int(result.exitCode),
			userInfo: [NSLocalizedDescriptionKey: errorMessage]
		))
	}
}
