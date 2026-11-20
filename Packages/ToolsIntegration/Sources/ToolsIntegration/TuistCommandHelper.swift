import Foundation

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
		runMode: GeneratorRunMode
	) async -> Result<String, Error> {
		let fullCommand = shellCommand(
			for: action,
			shouldOpenXcode: shouldOpenXcode,
			misePath: GeneratorRunMode.resolvedMisePath(misePath),
			runMode: runMode
		)

		return await GeneratorShell.run(fullCommand, at: path, errorDomain: "TuistError")
	}

	/// Builds the shell command that `runCommand` executes for the given action.
	internal static func shellCommand(
		for action: TuistAction,
		shouldOpenXcode: Bool,
		misePath: String,
		runMode: GeneratorRunMode
	) -> String {
		let commandString = action.commandString

		// Add --no-open flag for generate action when Xcode should not open
		let flags = ((action == .generate || action == .generateWithoutCache) && !shouldOpenXcode) ? " --no-open" : ""
		return runMode.command("tuist", arguments: commandString + flags, misePath: misePath)
	}
}
