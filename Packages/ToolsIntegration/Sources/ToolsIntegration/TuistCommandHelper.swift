import Foundation
import ProcessExecution

// MARK: - Tuist Action

public nonisolated enum TuistAction: Equatable {
	case generate
	case install
	case installUpdate
	case cache(TuistCacheType)
	case edit
	case inspectDependencies

	public var commandString: String {
		switch self {
		case .generate:
			"generate"

		case .install:
			"install"

		case .installUpdate:
			"install -u"

		case let .cache(type):
			"cache \(type.commandFlag)".trimmingCharacters(in: .whitespaces)

		case .edit:
			"edit"

		case .inspectDependencies:
			"inspect dependencies --only implicit"
		}
	}
}

// MARK: - Tuist Command Helper

public nonisolated enum TuistCommandHelper {

	/// Runs a Tuist command using mise exec at the specified repository path
	/// - Parameters:
	///   - action: The Tuist action to run
	///   - path: The repository path where the command should be executed
	///   - shouldOpenXcode: For generate action, controls whether Xcode opens after generation
	/// - Returns: A Result containing the command output on success or an error on failure
	public static func runCommand(
		_ action: TuistAction,
		at path: String,
		shouldOpenXcode: Bool,
		misePath: String,
		runMode: TuistRunMode
	) async -> Result<String, Error> {
		let commandString = action.commandString

		// Add --no-open flag for generate action when Xcode should not open
		let flags = (action == .generate && !shouldOpenXcode) ? " --no-open" : ""
		let fullCommand: String
		switch runMode {
		case .mise:
			fullCommand = "\(misePath) exec -- tuist \(commandString)\(flags)"
		case .native:
			fullCommand = "tuist \(commandString)\(flags)"
		}

		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/bin/zsh"),
			arguments: ["-i", "-c", fullCommand],
			currentDirectory: URL(fileURLWithPath: path),
			environment: EnvironmentHelper.setupEnvironment()
		)

		if result.success {
			let combined = [result.outputString, result.errorString]
				.filter { !$0.isEmpty }
				.joined(separator: "\n")
			return .success(combined.trimmingCharacters(in: .whitespacesAndNewlines))
		}
		else {
			let errorMessage = result.errorString.isEmpty
				? "Command failed with exit code \(result.exitCode)"
				: result.errorString
			let error = NSError(
				domain: "TuistError",
				code: Int(result.exitCode),
				userInfo: [NSLocalizedDescriptionKey: errorMessage]
			)
			return .failure(error)
		}
	}
}
