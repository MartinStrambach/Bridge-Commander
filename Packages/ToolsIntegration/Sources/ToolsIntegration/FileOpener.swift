import Foundation
import ProcessExecution
import Sharing
import UniformTypeIdentifiers

public nonisolated enum FileOpener {

	/// Opens a file the way `openFileInIDE(atPath:line:repositoryPath:xcodeProjectPath:)` does
	/// - Parameters:
	///   - filePath: Relative path to the file
	///   - repositoryPath: Absolute path to the repository
	///   - xcodeProjectPath: Path to .xcworkspace or .xcodeproj, if available
	public static func openFileInIDE(
		filePath: String,
		repositoryPath: String,
		xcodeProjectPath: String? = nil
	) async throws {
		try await openFileInIDE(
			atPath: (repositoryPath as NSString).appendingPathComponent(filePath),
			repositoryPath: repositoryPath,
			xcodeProjectPath: xcodeProjectPath
		)
	}

	/// Opens a file in its default application, the way `FileOpenAction` decides: a file that could
	/// run goes to the source-code editor instead, and one no application claims to the application
	/// chosen for its type in Bridge Commander, asked for the first time
	/// - Parameters:
	///   - fullPath: Absolute path to the file, which need not lie inside the repository
	///   - line: The line to put the cursor on. Only Xcode and JetBrains IDEs are given it: `open`
	///     has no way to pass one to other applications
	///   - repositoryPath: Absolute path to the repository whose IDE project opens alongside
	///   - xcodeProjectPath: Path to .xcworkspace or .xcodeproj, if available
	public static func openFileInIDE(
		atPath fullPath: String,
		line: Int? = nil,
		repositoryPath: String,
		xcodeProjectPath: String? = nil
	) async throws {
		guard FileManager.default.fileExists(atPath: fullPath) else {
			throw FileOpenerError.failedToOpen("File does not exist")
		}

		let target = Target(path: fullPath, line: line, repositoryPath: repositoryPath, xcodeProjectPath: xcodeProjectPath)
		switch FileOpenAction(FileOpenAction.Facts(at: fullPath)) {
		case let .open(in: application):
			try await open(target, in: application)

		case .openInChosenApplication:
			// Cancelling the picker opens nothing, and is not an error.
			if let application = await chosenApplication(forFileAt: fullPath) {
				try await open(target, in: application)
			}

		case .openInEditor:
			if let editor = FileOpenAction.editorApplication() {
				try await open(target, in: editor)
			}
			else {
				try await run("/usr/bin/open", arguments: ["-R", fullPath])
			}

		case .openFolder:
			try await run("/usr/bin/open", arguments: [fullPath])

		case .revealInFinder:
			try await run("/usr/bin/open", arguments: ["-R", fullPath])
		}
	}

	private struct Target {
		var path: String
		var line: Int?
		var repositoryPath: String
		var xcodeProjectPath: String?
	}

	/// Opens the file in the application, passing the line to the IDEs that take one.
	private static func open(_ target: Target, in application: URL) async throws {
		let lineArguments = target.line.map { ["--line", String($0)] } ?? []

		switch FileOpenApplicationKind(bundleIdentifier: FileOpenApplications.bundleIdentifier(ofApplicationAt: application)) {
		case .xcode:
			// Only for source code: Xcode is the default application for many plain files
			// (`.json`, `.md`), and a workspace is a heavy thing to open for a glance at one.
			if let xcodeProjectPath = target.xcodeProjectPath, FileOpenApplicationKind.isSourceCode(target.path) {
				try await XcodeProjectGenerator.openProject(at: xcodeProjectPath)
			}
			try await run("/usr/bin/xed", arguments: lineArguments + [target.path])

		case let .jetBrains(bundleIdentifier):
			// The repository first, so the file opens in its project rather than on its own.
			try await AndroidStudioLauncher.openProject(
				at: target.repositoryPath,
				in: application.path,
				bundleIdentifier: bundleIdentifier
			)
			// `-n` starts a new launcher process, which hands its arguments to the running IDE and
			// exits; a plain `open -a` would drop them when the IDE is already running.
			try await run("/usr/bin/open", arguments: ["-na", application.path, "--args"] + lineArguments + [target.path])

		case .other:
			try await run("/usr/bin/open", arguments: ["-a", application.path, target.path])
		}
	}

	/// The application chosen for the file's type, asking for one when none is.
	private static func chosenApplication(forFileAt path: String) async -> URL? {
		@Shared(.fileOpenApplications) var choices = FileOpenApplications()
		let fileType = FileOpenApplications.fileType(ofFileAt: path)
		if let application = choices.application(forFileType: fileType) {
			return application
		}

		guard let choice = await ApplicationPicker.choose(forFileAt: path) else {
			return nil
		}
		if choice.remember, let bundleIdentifier = FileOpenApplications.bundleIdentifier(ofApplicationAt: choice.application) {
			$choices.withLock { $0.bundleIdentifiers[fileType] = bundleIdentifier }
		}
		return choice.application
	}

	private static func run(_ executablePath: String, arguments: [String]) async throws {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: executablePath),
			arguments: arguments
		)
		guard result.success else {
			let errorMsg = result.trimmedError
			throw FileOpenerError
				.failedToOpen(errorMsg.isEmpty ? "Unknown error (exit code \(result.exitCode))" : errorMsg)
		}
	}
}

// MARK: - Applications

/// How `FileOpener` hands a file to an application, told apart by its bundle identifier.
enum FileOpenApplicationKind: Equatable {
	/// Reached through `xed`, which takes a line.
	case xcode
	/// IntelliJ IDEA, Android Studio and their siblings, whose launcher takes `--line`.
	case jetBrains(bundleIdentifier: String)
	/// Reached through `open -a`.
	case other

	/// JetBrains applications that are not IDEs taking a file on their command line.
	private static let jetBrainsNonIDEs: Set = ["com.jetbrains.fleet", "com.jetbrains.gateway", "com.jetbrains.toolbox"]

	init(bundleIdentifier: String?) {
		guard let bundleIdentifier else {
			self = .other
			return
		}
		if bundleIdentifier == "com.apple.dt.Xcode" {
			self = .xcode
		}
		else if
			bundleIdentifier.hasPrefix(AndroidStudioDetector.bundleIdentifier)
			|| (bundleIdentifier.hasPrefix("com.jetbrains.") && !Self.jetBrainsNonIDEs.contains(bundleIdentifier))
		{
			self = .jetBrains(bundleIdentifier: bundleIdentifier)
		}
		else {
			self = .other
		}
	}

	/// Whether the file's type is source code, which an IDE opens inside its project.
	static func isSourceCode(_ path: String) -> Bool {
		UTType(filenameExtension: (path as NSString).pathExtension)?.conforms(to: .sourceCode) ?? false
	}
}

// MARK: - Errors

public enum FileOpenerError: Error, LocalizedError {
	case failedToOpen(String)

	public var errorDescription: String? {
		switch self {
		case let .failedToOpen(message):
			"Failed to open file: \(message)"
		}
	}
}
