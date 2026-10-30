import Foundation
import GitHosting
import Sharing
import ToolsIntegration

/// Bridge Commander's settings as one JSON file, for Settings ▸ General ▸ Backup.
///
/// Every setting is optional: a file only changes what it names, so a file written by an older
/// version (which knows fewer settings) or a newer one (whose extra keys are ignored) still
/// imports. Enum settings are stored as their raw values and skipped on import when this version
/// no longer knows the value.
///
/// A setting added to `SettingsReducer.State` is not exported until it is added here, in
/// `init(state:includesTokens:exportedAt:)` and in `apply(to:)`.
public struct SettingsBackup: Codable, Equatable, Sendable {
	/// Bumped only for a change an older reader would misread; added settings do not need it.
	public static let currentFormatVersion = 1

	/// Present in every file this type writes; its absence identifies a JSON file that is not a
	/// settings backup.
	public var formatVersion: Int
	public var exportedAt: Date?

	// Accounts. Written only when the user chooses to include them.
	public var youtrackAuthToken: String?
	public var githubToken: String?
	public var gitlabToken: String?
	/// `GitHubOwnerTokens.tokens`: GitHub owner to the token used for its repositories.
	public var githubOwnerTokens: [String: String]?

	// General
	public var uiFontSize: Double?
	public var periodicRefreshInterval: Int?

	// Repository rows
	public var repositoryRowLayout: RepositoryRowLayout?

	// Repository groups. Group settings are keyed by repository path, so the paths travel with
	// them.
	public var trackedRepoPaths: [String]?
	public var groupSettings: [String: RepoGroupSettings]?

	// Branches & worktrees
	public var branchNameRegex: String?
	public var ticketBranchNameTemplate: String?
	public var worktreeBasePath: String?
	public var deleteDerivedDataOnWorktreeDelete: Bool?

	// Terminal
	public var terminalFontName: String?
	public var terminalFontSize: Double?
	public var terminalColorTheme: String?
	public var terminalProfiles: [TerminalProfile]?
	public var terminalCopyOnSelect: Bool?
	public var terminalMouseReporting: Bool?
	public var terminalReadsImageFiles: Bool?
	public var terminalRocketBuddy: Bool?
	public var terminalStartupCommand: String?
	public var terminalStartupCommandInNewTabs: Bool?
	public var terminalNotifications: Bool?
	public var terminalNotificationSource: String?

	// External apps
	public var terminalApp: String?
	public var terminalOpeningBehavior: String?
	public var claudeCodeOpeningBehavior: String?
	/// `FileOpenApplications.bundleIdentifiers`: file type to application bundle identifier.
	public var fileOpenApplications: [String: String]?

	// Tuist
	public var tuistRunMode: String?
	public var misePath: String?
	public var tuistCacheType: String?
	public var openXcodeAfterGenerate: Bool?

	// Activity log
	public var activityLogIncludesReadOnlyGitCommands: Bool?

	public init(formatVersion: Int = Self.currentFormatVersion) {
		self.formatVersion = formatVersion
	}

	/// The current settings. Tokens are left out unless `includesTokens`: the file is plain text,
	/// and a backup is easily shared or synced somewhere a token should not go.
	public init(state: SettingsReducer.State, includesTokens: Bool, exportedAt: Date) {
		self.init()
		self.exportedAt = exportedAt

		if includesTokens {
			youtrackAuthToken = state.youtrackAuthToken
			githubToken = state.githubToken
			gitlabToken = state.gitlabToken
			// Only with tokens: an owner listed without one says nothing worth restoring.
			if state.githubOwnerTokens.hasTokens {
				githubOwnerTokens = state.githubOwnerTokens.tokens.filter { !$0.value.isEmpty }
			}
		}

		uiFontSize = state.uiFontSize
		periodicRefreshInterval = state.periodicRefreshInterval.rawValue
		repositoryRowLayout = state.repositoryRowLayout
		trackedRepoPaths = state.trackedRepoPaths
		groupSettings = state.groupSettings

		branchNameRegex = state.branchNameRegex
		ticketBranchNameTemplate = state.ticketBranchNameTemplate
		worktreeBasePath = state.worktreeBasePath
		deleteDerivedDataOnWorktreeDelete = state.deleteDerivedDataOnWorktreeDelete

		terminalFontName = state.terminalFontName
		terminalFontSize = state.terminalFontSize
		terminalColorTheme = state.terminalColorTheme.rawValue
		terminalProfiles = state.terminalProfiles
		terminalCopyOnSelect = state.terminalCopyOnSelect
		terminalMouseReporting = state.terminalMouseReporting
		terminalReadsImageFiles = state.terminalReadsImageFiles
		terminalRocketBuddy = state.terminalRocketBuddy
		terminalStartupCommand = state.terminalStartupCommand
		terminalStartupCommandInNewTabs = state.terminalStartupCommandInNewTabs
		terminalNotifications = state.terminalNotifications
		terminalNotificationSource = state.terminalNotificationSource.rawValue

		terminalApp = state.terminalApp.rawValue
		terminalOpeningBehavior = state.terminalOpeningBehavior.rawValue
		claudeCodeOpeningBehavior = state.claudeCodeOpeningBehavior.rawValue
		fileOpenApplications = state.fileOpenApplications.bundleIdentifiers

		tuistRunMode = state.tuistRunMode.rawValue
		misePath = state.misePath
		tuistCacheType = state.tuistCacheType.rawValue
		openXcodeAfterGenerate = state.openXcodeAfterGenerate

		activityLogIncludesReadOnlyGitCommands = state.activityLogIncludesReadOnlyGitCommands
	}

	/// Whether the file carries any access token, so importing it replaces the user's.
	public var includesTokens: Bool {
		youtrackAuthToken != nil || githubToken != nil || gitlabToken != nil || githubOwnerTokens != nil
	}

	/// Writes every setting the file names into `state`.
	///
	/// Plain settings are replaced. Collections are merged instead, so importing a backup does not
	/// drop what was set up since it was made: repositories missing from the current list are
	/// appended, group settings and terminal profiles in the file replace those with the same
	/// path or name and leave the others alone.
	public func apply(to state: inout SettingsReducer.State) {
		// Trimmed like a pasted token: a hand-edited file can carry a trailing newline, which
		// corrupts the Bearer header.
		func token(_ value: String) -> String {
			value.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		if let youtrackAuthToken { state.$youtrackAuthToken.withLock { $0 = token(youtrackAuthToken) } }
		if let githubToken { state.$githubToken.withLock { $0 = token(githubToken) } }
		if let gitlabToken { state.$gitlabToken.withLock { $0 = token(gitlabToken) } }
		// Merged like the other collections: an owner in the file replaces the same owner's token
		// and leaves the others alone.
		if let githubOwnerTokens {
			state.$githubOwnerTokens.withLock { tokens in
				for (owner, value) in githubOwnerTokens.sorted(by: { $0.key < $1.key }) {
					tokens.setToken(value, forOwner: owner)
				}
			}
		}

		if let uiFontSize { state.$uiFontSize.withLock { $0 = UIFontSize.clamped(uiFontSize) } }
		set(\.$periodicRefreshInterval, periodicRefreshInterval.flatMap(PeriodicRefreshInterval.init(rawValue:)), in: &state)
		set(\.$repositoryRowLayout, repositoryRowLayout, in: &state)
		if let trackedRepoPaths {
			state.$trackedRepoPaths.withLock { paths in
				var tracked = Set(paths.map(Self.standardizedPath))
				for path in trackedRepoPaths where tracked.insert(Self.standardizedPath(path)).inserted {
					paths.append(path)
				}
			}
		}
		if let groupSettings {
			state.$groupSettings.withLock { $0.merge(groupSettings) { _, imported in imported } }
		}

		set(\.$branchNameRegex, branchNameRegex, in: &state)
		set(\.$ticketBranchNameTemplate, ticketBranchNameTemplate, in: &state)
		set(\.$worktreeBasePath, worktreeBasePath, in: &state)
		set(\.$deleteDerivedDataOnWorktreeDelete, deleteDerivedDataOnWorktreeDelete, in: &state)

		set(\.$terminalFontName, terminalFontName, in: &state)
		if let terminalFontSize {
			state.$terminalFontSize.withLock { $0 = TerminalFontSize.clamped(terminalFontSize) }
		}
		// Profiles before the theme, which can name one of them.
		if let terminalProfiles {
			state.$terminalProfiles.withLock { $0 = SettingsReducer.merge(terminalProfiles, into: $0) }
		}
		set(\.$terminalColorTheme, terminalColorTheme.flatMap(TerminalThemeSelection.init(rawValue:)), in: &state)
		set(\.$terminalCopyOnSelect, terminalCopyOnSelect, in: &state)
		set(\.$terminalMouseReporting, terminalMouseReporting, in: &state)
		set(\.$terminalReadsImageFiles, terminalReadsImageFiles, in: &state)
		set(\.$terminalRocketBuddy, terminalRocketBuddy, in: &state)
		set(\.$terminalStartupCommand, terminalStartupCommand, in: &state)
		set(\.$terminalStartupCommandInNewTabs, terminalStartupCommandInNewTabs, in: &state)
		set(\.$terminalNotifications, terminalNotifications, in: &state)
		set(
			\.$terminalNotificationSource,
			terminalNotificationSource.flatMap(TerminalNotificationSource.init(rawValue:)),
			in: &state
		)

		set(\.$terminalApp, terminalApp.flatMap(TerminalApp.init(rawValue:)), in: &state)
		set(\.$terminalOpeningBehavior, terminalOpeningBehavior.flatMap(TerminalOpeningBehavior.init(rawValue:)), in: &state)
		set(\.$claudeCodeOpeningBehavior, claudeCodeOpeningBehavior.flatMap(TerminalOpeningBehavior.init(rawValue:)), in: &state)
		set(\.$fileOpenApplications, fileOpenApplications.map(FileOpenApplications.init(bundleIdentifiers:)), in: &state)

		set(\.$tuistRunMode, tuistRunMode.flatMap(TuistRunMode.init(rawValue:)), in: &state)
		set(\.$misePath, misePath, in: &state)
		set(\.$tuistCacheType, tuistCacheType.flatMap(TuistCacheType.init(rawValue:)), in: &state)
		set(\.$openXcodeAfterGenerate, openXcodeAfterGenerate, in: &state)

		set(\.$activityLogIncludesReadOnlyGitCommands, activityLogIncludesReadOnlyGitCommands, in: &state)
	}

	private func set<Value>(
		_ keyPath: KeyPath<SettingsReducer.State, Shared<Value>>,
		_ value: Value?,
		in state: inout SettingsReducer.State
	) {
		guard let value else { return }
		state[keyPath: keyPath].withLock { $0 = value }
	}

	// MARK: - File format

	public func encoded() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		encoder.dateEncodingStrategy = .iso8601
		return try encoder.encode(self)
	}

	public static func decoded(from data: Data) throws -> SettingsBackup {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let backup: SettingsBackup
		do {
			backup = try decoder.decode(Self.self, from: data)
		}
		catch {
			throw SettingsBackupError.notASettingsBackup
		}
		guard backup.startupCommands.allSatisfy(Self.isSingleLine) else {
			throw SettingsBackupError.unsafeStartupCommand
		}
		return backup.withStandardizedPaths()
	}

	/// The global and every group's terminal startup command, each typed into new tabs.
	private var startupCommands: [String] {
		[terminalStartupCommand].compactMap(\.self)
			+ (groupSettings ?? [:]).values.map(\.terminalStartupCommand)
	}

	/// A startup command is typed into the shell as stored, followed by Return. Settings only
	/// accepts one line, but a file can hold line breaks (more commands run), escape sequences or
	/// ⌃C — none visible in the import confirmation, so what the user approved would not be what
	/// is typed. Such a file was not written by this app, and is refused whole.
	static func isSingleLine(_ command: String) -> Bool {
		command.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
	}

	/// Repository paths in the form the repository list stores them (`addRepository` standardizes
	/// what it tracks), so `/repos/app/` in a hand-edited file matches a tracked `/repos/app`
	/// instead of being tracked twice.
	func withStandardizedPaths() -> SettingsBackup {
		var backup = self
		if let trackedRepoPaths {
			var seen = Set<String>()
			backup.trackedRepoPaths = trackedRepoPaths
				.map(Self.standardizedPath)
				.filter { seen.insert($0).inserted }
		}
		if let groupSettings {
			backup.groupSettings = Dictionary(
				groupSettings.map { (Self.standardizedPath($0.key), $0.value) },
				uniquingKeysWith: { first, _ in first }
			)
		}
		return backup
	}

	static func standardizedPath(_ path: String) -> String {
		URL(fileURLWithPath: path).standardizedFileURL.path
	}

	/// Shell commands the file would put in place of the current ones: the global and per-group
	/// terminal startup commands, typed into new terminal tabs, and the mise executable Tuist runs.
	/// Listed in the import confirmation, since a backup from someone else could carry any command.
	public func commandsChanged(from state: SettingsReducer.State) -> [String] {
		var commands: [String] = []
		if let terminalStartupCommand, !terminalStartupCommand.isEmpty,
		   terminalStartupCommand != state.terminalStartupCommand {
			commands.append("Terminal startup command: \(terminalStartupCommand)")
		}
		for (path, settings) in (groupSettings ?? [:]).sorted(by: { $0.key < $1.key }) {
			let command = settings.terminalStartupCommand
			guard !command.isEmpty, command != state.groupSettings[path]?.terminalStartupCommand else { continue }
			// The full path: two groups can share a folder name.
			commands.append("Startup command for \((path as NSString).abbreviatingWithTildeInPath): \(command)")
		}
		if let misePath, misePath != state.misePath {
			commands.append("mise executable: \(misePath)")
		}
		return commands
	}

	/// The suggested name of an exported file.
	public static func defaultFilename(exportedAt date: Date) -> String {
		"Bridge Commander Settings \(date.formatted(.iso8601.year().month().day())).json"
	}
}

public enum SettingsBackupError: LocalizedError, Equatable {
	case notASettingsBackup
	case unsafeStartupCommand

	public var errorDescription: String? {
		switch self {
		case .notASettingsBackup:
			"The file is not a Bridge Commander settings file, or it is damaged."

		case .unsafeStartupCommand:
			"The file contains a terminal startup command with line breaks or control characters. Bridge Commander does not write such files, so nothing was imported."
		}
	}
}
