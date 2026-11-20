import Dependencies
import DependenciesMacros
import Foundation

// MARK: - XcodeGen Action

/// An `xcodegen` command the XcodeGen menu runs in the Xcode project path, where the spec lives.
public nonisolated enum XcodeGenAction: Equatable, Sendable {
	case generate
	/// Regenerates only when the spec or the files it lists changed since the last cached run.
	case generateUsingCache
	/// The spec as XcodeGen resolves it, summarised (targets, configs, schemes).
	case dumpSummary

	public var commandString: String {
		switch self {
		case .generate:
			"generate"
		case .generateUsingCache:
			"generate --use-cache"
		case .dumpSummary:
			"dump --type summary"
		}
	}

	/// Whether the command writes the Xcode project, after which it can be opened.
	public var generatesProject: Bool {
		switch self {
		case .generate, .generateUsingCache: true
		case .dumpSummary: false
		}
	}
}

// MARK: - XcodeGen Command Helper

public nonisolated enum XcodeGenCommandHelper {
	/// Runs an XcodeGen command at `path`, through mise or straight from `PATH`.
	/// XcodeGen never opens Xcode itself; the caller does when it should.
	/// - Returns: the command's output on success, or an error carrying its stderr
	public static func runCommand(
		_ action: XcodeGenAction,
		at path: String,
		misePath: String,
		runMode: GeneratorRunMode
	) async -> Result<String, Error> {
		await GeneratorShell.run(
			shellCommand(for: action, misePath: GeneratorRunMode.resolvedMisePath(misePath), runMode: runMode),
			at: path,
			errorDomain: "XcodeGenError"
		)
	}

	/// Builds the shell command that `runCommand` executes for the given action.
	static func shellCommand(for action: XcodeGenAction, misePath: String, runMode: GeneratorRunMode) -> String {
		runMode.command("xcodegen", arguments: action.commandString, misePath: misePath)
	}
}

// MARK: - XcodeGen Client

@DependencyClient
public struct XcodeGenClient: Sendable {
	/// Runs an XcodeGen command in a folder; see `XcodeGenCommandHelper.runCommand`.
	public var run: @Sendable (
		_ action: XcodeGenAction,
		_ at: String,
		_ misePath: String,
		_ runMode: GeneratorRunMode
	) async -> Result<String, Error> = { _, _, _, _ in .success("") }
	/// Opens the spec in the Xcode project path (`project.yml`, else `project.json`) in its default
	/// application; throws when the folder has neither.
	public var openSpec: @Sendable (_ repositoryPath: String, _ iosSubfolderPath: String) async throws -> Void
}

/// The Xcode project path has no XcodeGen spec to open.
public struct XcodeGenSpecNotFoundError: LocalizedError {
	public init() {}

	public var errorDescription: String? {
		"No project.yml or project.json found in the Xcode project path."
	}
}

extension XcodeGenClient: DependencyKey {
	public static let liveValue = XcodeGenClient(
		run: { action, path, misePath, runMode in
			await XcodeGenCommandHelper.runCommand(action, at: path, misePath: misePath, runMode: runMode)
		},
		openSpec: { repositoryPath, iosSubfolderPath in
			guard
				let specPath = XcodeProjectDetector.xcodeGenSpecPath(
					in: repositoryPath,
					iosSubfolderPath: iosSubfolderPath
				)
			else {
				throw XcodeGenSpecNotFoundError()
			}
			try await FileOpener.openFileInIDE(atPath: specPath, repositoryPath: repositoryPath)
		}
	)
}

extension XcodeGenClient: TestDependencyKey {
	public static let testValue = XcodeGenClient()
}
