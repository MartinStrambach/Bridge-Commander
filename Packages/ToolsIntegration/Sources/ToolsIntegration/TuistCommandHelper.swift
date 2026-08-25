import Foundation
import ProcessExecution

// MARK: - Tuist Action

public nonisolated enum TuistAction: Equatable, Sendable {
	case generate
	case generateWithoutCache
	case install
	case installUpdate
	case installCacheAndGenerate(TuistCacheType)
	case cache(TuistCacheType)
	case edit
	case inspectDependencies
	/// A `nil` category cleans every category, matching the CLI's default.
	case clean(TuistCleanCategory?)

	public var commandString: String {
		switch self {
		case .generate:
			"generate"

		case .generateWithoutCache:
			"generate --cache-profile none"

		case .install:
			"install"

		case .installUpdate:
			"install -u"

		case .installCacheAndGenerate:
			""

		case let .cache(type):
			"cache \(type.commandFlag)".trimmingCharacters(in: .whitespaces)

		case .edit:
			"edit"

		case .inspectDependencies:
			"inspect dependencies --only implicit"

		case let .clean(category):
			"clean \(category?.rawValue ?? "")".trimmingCharacters(in: .whitespaces)
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
		let fullCommand = shellCommand(
			for: action,
			shouldOpenXcode: shouldOpenXcode,
			misePath: misePath,
			runMode: runMode
		)

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

	/// Builds the shell command that `runCommand` executes for the given action.
	internal static func shellCommand(
		for action: TuistAction,
		shouldOpenXcode: Bool,
		misePath: String,
		runMode: TuistRunMode
	) -> String {
		let commandString = action.commandString

		// Add --no-open flag for generate action when Xcode should not open
		let flags = ((action == .generate || action == .generateWithoutCache) && !shouldOpenXcode) ? " --no-open" : ""
		switch runMode {
		case .mise:
			return "\(misePath) exec -- tuist \(commandString)\(flags)"
		case .native:
			return "tuist \(commandString)\(flags)"
		}
	}
}
