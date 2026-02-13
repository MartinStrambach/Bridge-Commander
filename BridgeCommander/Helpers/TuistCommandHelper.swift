import Foundation

// MARK: - Tuist Cache Type

nonisolated enum TuistCacheType: String, Equatable, CaseIterable, Sendable {
	case externalOnly
	case all

	var displayName: String {
		switch self {
		case .externalOnly:
			"External Only"

		case .all:
			"All Targets"
		}
	}

	var commandFlag: String {
		switch self {
		case .externalOnly:
			"--external-only"

		case .all:
			""
		}
	}
}

// MARK: - Tuist Action

nonisolated enum TuistAction: Equatable {
	case generate
	case install
	case cache(TuistCacheType)
	case edit

	var commandString: String {
		switch self {
		case .generate:
			"generate"

		case .install:
			"install"

		case let .cache(type):
			"cache \(type.commandFlag)".trimmingCharacters(in: .whitespaces)

		case .edit:
			"edit"
		}
	}
}

// MARK: - Tuist Command Helper

nonisolated enum TuistCommandHelper {
	/// Runs a Tuist command using mise exec at the specified repository path
	/// - Parameters:
	///   - action: The Tuist action to run
	///   - path: The repository path where the command should be executed
	///   - shouldOpenXcode: For generate action, controls whether Xcode opens after generation
	/// - Returns: A Result containing the command output on success or an error on failure
	static func runCommand(
		_ action: TuistAction,
		at path: String,
		shouldOpenXcode: Bool
	) async -> Result<String, Error> {
		// Replace 'mise exec' with full path to mise for compatibility in sandbox
		let misePath = NSHomeDirectory() + "/.local/bin/mise"
		let commandString = action.commandString

		// Add --no-open flag for generate action when Xcode should not open
		let flags = (action == .generate && !shouldOpenXcode) ? " --no-open" : ""
		let fullCommand = "\(misePath) exec -- tuist \(commandString)\(flags)"

		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/bin/zsh"),
			arguments: ["-c", fullCommand],
			currentDirectory: URL(fileURLWithPath: path),
			environment: GitEnvironmentHelper.setupEnvironment()
		)

		if result.success {
			return .success(result.outputString)
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
