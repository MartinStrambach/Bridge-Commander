import ComposableArchitecture
import Foundation
import GitHosting
import ToolsIntegration

/// Outcome of a "Test Connection" run against a hosting provider token.
public enum TokenTestState: Equatable, Sendable {
	case idle
	case testing
	case success(username: String)
	case failure(message: String)
}

@Reducer
public struct SettingsReducer {
	@ObservableState
	public struct State: Equatable {
		@Shared(.youtrackAuthToken)
		public var youtrackAuthToken = ""

		@Shared(.githubToken)
		public var githubToken = ""

		@Shared(.gitlabToken)
		public var gitlabToken = ""

		@Shared(.periodicRefreshInterval)
		public var periodicRefreshInterval = PeriodicRefreshInterval.fiveMinutes

		@Shared(.groupSettings)
		public var groupSettings: [String: RepoGroupSettings] = [:]

		@Shared(.trackedRepoPaths)
		public var trackedRepoPaths: [String] = []

		@Shared(.branchNameRegex)
		public var branchNameRegex = "[a-zA-Z]+-\\d+[_/]"

		@Shared(.ticketBranchNameTemplate)
		public var ticketBranchNameTemplate = BranchNameFormatter.defaultTicketBranchTemplate

		@Shared(.openXcodeAfterGenerate)
		public var openXcodeAfterGenerate = true

		@Shared(.deleteDerivedDataOnWorktreeDelete)
		public var deleteDerivedDataOnWorktreeDelete = true

		@Shared(.tuistCacheType)
		public var tuistCacheType = TuistCacheType.externalOnly

		@Shared(.terminalApp)
		public var terminalApp = TerminalApp.systemTerminal

		@Shared(.terminalOpeningBehavior)
		public var terminalOpeningBehavior = TerminalOpeningBehavior.newTab

		@Shared(.claudeCodeOpeningBehavior)
		public var claudeCodeOpeningBehavior = TerminalOpeningBehavior.newWindow

		@Shared(.androidStudioPath)
		public var androidStudioPath = "/Applications/Android Studio.app/Contents/MacOS/studio"

		@Shared(.misePath)
		public var misePath = NSHomeDirectory() + "/.local/bin/mise"

		@Shared(.tuistRunMode)
		public var tuistRunMode = TuistRunMode.mise

		@Shared(.worktreeBasePath)
		public var worktreeBasePath = "../worktrees"

		/// Read only: what a group that has not picked its own dialog tab shows in its picker.
		@Shared(.defaultWorktreeSource)
		public var defaultWorktreeSource = WorktreeSource.branch

		@Shared(.terminalColorTheme)
		public var terminalColorTheme = TerminalThemeSelection.builtIn(.basicDark)

		@Shared(.terminalProfiles)
		public var terminalProfiles: [TerminalProfile] = []

		@Shared(.terminalCopyOnSelect)
		public var terminalCopyOnSelect = false

		@Shared(.terminalMouseReporting)
		public var terminalMouseReporting = true

		@Shared(.terminalStartupCommand)
		public var terminalStartupCommand = ""

		@Shared(.terminalStartupCommandInNewTabs)
		public var terminalStartupCommandInNewTabs = false

		@Shared(.terminalNotifications)
		public var terminalNotifications = true

		@Shared(.terminalClaudeStatusDetection)
		public var terminalClaudeStatusDetection = ClaudeStatusDetection.default

		@Shared(.terminalFontSize)
		public var terminalFontSize = TerminalFontSize.default

		@Shared(.terminalFontName)
		public var terminalFontName = TerminalFontFamily.systemDefault

		@Shared(.uiFontSize)
		public var uiFontSize = UIFontSize.default

		public var youtrackTokenTest = TokenTestState.idle
		public var githubTokenTest = TokenTestState.idle
		public var gitlabTokenTest = TokenTestState.idle

		@Presents
		public var alert: AlertState<Action.Alert>?

		public init() {}
	}

	public enum Action {
		case setYouTrackToken(String)
		case setGitHubToken(String)
		case setGitLabToken(String)
		case clearGitHubToken
		case clearGitLabToken
		case testYouTrackTokenButtonTapped
		case testGitHubTokenButtonTapped
		case testGitLabTokenButtonTapped
		case youTrackTokenTestFinished(TokenTestState)
		case gitHubTokenTestFinished(TokenTestState)
		case gitLabTokenTestFinished(TokenTestState)
		case setPeriodicRefreshInterval(PeriodicRefreshInterval)
		case setGroupSupportsIOS(groupId: String, value: Bool)
		case setGroupSupportsAndroid(groupId: String, value: Bool)
		case setGroupMobileSubfolderPath(groupId: String, path: String)
		case setGroupIOSSubfolderPath(groupId: String, path: String)
		case setGroupSupportsTuist(groupId: String, value: Bool)
		case setGroupTicketIdRegex(groupId: String, regex: String)
		case setGroupXcodeFilePreference(groupId: String, preference: XcodeFilePreference)
		case setGroupWorktreeCopyPaths(groupId: String, value: [String])
		case setGroupSupportsWeb(groupId: String, value: Bool)
		case setGroupWebIndexPath(groupId: String, path: String)
		case setGroupDefaultBranch(groupId: String, value: String)
		case setGroupYouTrackBaseURL(groupId: String, value: String)
		case setGroupTerminalStartupCommand(groupId: String, value: String)
		case setGroupSkipGlobalTerminalStartupCommand(groupId: String, value: Bool)
		case setGroupDefaultWorktreeSource(groupId: String, source: WorktreeSource)
		case setBranchNameRegex(String)
		case setTicketBranchNameTemplate(String)
		case setOpenXcodeAfterGenerate(Bool)
		case setDeleteDerivedDataOnWorktreeDelete(Bool)
		case setTuistCacheType(TuistCacheType)
		case setTerminalApp(TerminalApp)
		case setTerminalOpeningBehavior(TerminalOpeningBehavior)
		case setClaudeCodeOpeningBehavior(TerminalOpeningBehavior)
		case setAndroidStudioPath(String)
		case setWorktreeBasePath(String)
		case setMisePath(String)
		case setTuistRunMode(TuistRunMode)
		case setTerminalColorTheme(TerminalThemeSelection)
		case setTerminalCopyOnSelect(Bool)
		case setTerminalMouseReporting(Bool)
		case setTerminalStartupCommand(String)
		case setTerminalStartupCommandInNewTabs(Bool)
		case setTerminalNotifications(Bool)
		case setTerminalClaudeStatusDetection(ClaudeStatusDetection)
		case setTerminalFontSize(Double)
		case setTerminalFontName(String)
		case setUIFontSize(Double)
		case importFromTerminalAppButtonTapped
		case profileFilesSelected([URL])
		case profilesImported([TerminalProfile])
		case profileImportFailed(message: String)
		case deleteProfileButtonTapped(name: String)
		case clearTokenButtonTapped
		case alert(PresentationAction<Alert>)

		@CasePathable
		public enum Alert {
			case confirmClearToken
		}
	}

	@Dependency(TokenVerificationClient.self)
	private var tokenVerification

	@Dependency(YouTrackClient.self)
	private var youtrack

	@Dependency(TerminalProfileImportClient.self)
	private var profileImport

	public init() {}

	/// Adds imported profiles to the stored list, replacing any with the same name.
	///
	/// Replacing rather than uniquifying is what makes re-importing after an edit in Terminal.app
	/// behave: the name is the profile's identity on both sides, so "Solarized Dark" imported
	/// twice is one updated profile, not "Solarized Dark" and "Solarized Dark 2".
	static func merge(_ imported: [TerminalProfile], into existing: [TerminalProfile]) -> [TerminalProfile] {
		var merged = existing
		for profile in imported {
			if let index = merged.firstIndex(where: { $0.name == profile.name }) {
				merged[index] = profile
			}
			else {
				merged.append(profile)
			}
		}
		return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}

	/// Adopts an imported profile's font when that profile is picked as the terminal's theme.
	///
	/// A font is part of a profile in Terminal.app, so selecting one here brings its typeface
	/// along with its colors — which does mean a theme switch overwrites a font chosen by hand in
	/// this pane, the same way it overwrites the colors.
	///
	/// The size applies whenever the profile carries one, because any point size is renderable.
	/// The family only applies when it still resolves: several of Terminal's profiles name faces
	/// bundled inside Terminal.app that `NSFont(name:size:)` cannot find, and storing one would
	/// silently drop the terminal onto the system face — worse than leaving the current typeface
	/// alone, and invisible in the font picker, which only lists installed families.
	static func adoptProfileFont(for selection: TerminalThemeSelection, in state: inout State) {
		guard
			case let .imported(name) = selection,
			let font = state.terminalProfiles.first(where: { $0.name == name })?.font
		else { return }

		state.$terminalFontSize.withLock { $0 = TerminalFontSize.clamped(font.size) }
		guard font.isAvailable else { return }
		state.$terminalFontName.withLock { $0 = font.name }
	}

	/// Runs a verification call and condenses its result into displayable state.
	private static func tokenTestOutcome(
		provider: PullRequestProvider,
		_ verify: @Sendable () async throws -> String
	) async -> TokenTestState {
		do {
			return try await .success(username: verify())
		}
		catch {
			return .failure(message: tokenTestFailureMessage(for: error, provider: provider))
		}
	}

	/// The YouTrack instances the token is used against: each tracked group's URL, once, in the
	/// order the groups are listed. The token is global but the URL is per group, so a test has to
	/// name an instance — and a token can work on one instance and not another.
	static func youTrackInstances(in state: State) -> [String] {
		var instances: [String] = []
		var seen = Set<String>()
		for groupId in state.trackedRepoPaths {
			let base = YouTrackURLBuilder.normalizedBase(state.groupSettings[groupId]?.youtrackBaseURL ?? "")
			if !base.isEmpty, seen.insert(base.lowercased()).inserted {
				instances.append(base)
			}
		}
		return instances
	}

	/// Folds the per-instance results into one verdict. Every line names its instance, so with
	/// several configured it is clear which one the token failed on.
	static func youTrackTokenTestOutcome(
		_ results: [(instance: String, result: Result<String, any Error>)]
	) -> TokenTestState {
		let logins = results.compactMap { try? $0.result.get() }
		if logins.count == results.count {
			return .success(username: zip(logins, results)
				.map { "\($0) on \(displayName(ofInstance: $1.instance))" }
				.joined(separator: ", "))
		}
		return .failure(message: results.map { instance, result in
			let outcome = switch result {
			case let .success(login): "authenticated as \(login)"
			case let .failure(error): youTrackTokenTestFailureMessage(for: error)
			}
			return "\(displayName(ofInstance: instance)): \(outcome)"
		}.joined(separator: "\n"))
	}

	/// The instance as a user recognizes it: its base URL without the scheme.
	private static func displayName(ofInstance base: String) -> String {
		base.replacing(/^https?:\/\//.ignoresCase(), with: "")
	}

	private static func youTrackTokenTestFailureMessage(for error: any Error) -> String {
		switch error {
		case YouTrackServiceError.httpFailure(statusCode: 401):
			"HTTP 401 — the token is invalid, revoked, or expired."

		case YouTrackServiceError.httpFailure(statusCode: 403):
			"HTTP 403 — the token lacks access; check that its scope includes YouTrack."

		// A wrong base URL tends to answer with a web page (200) or a 404, not with an auth error.
		case YouTrackServiceError.httpFailure(statusCode: 404),
		     YouTrackServiceError.unexpectedResponse:
			"no YouTrack API answered at this URL — check the group's YouTrack URL."

		case let YouTrackServiceError.httpFailure(statusCode):
			"HTTP \(statusCode)."

		case YouTrackServiceError.invalidURL:
			"the YouTrack URL is not a valid URL."

		default:
			error.localizedDescription
		}
	}

	/// Import errors carry their own wording; anything else falls back to the system message.
	static func importFailureMessage(_ error: Error) -> String {
		(error as? TerminalProfileImportError)?.errorDescription ?? error.localizedDescription
	}

	static func importSuccessMessage(_ profiles: [TerminalProfile]) -> String {
		let summary = profiles.count == 1
			? "Imported “\(profiles[0].name)”."
			: "Imported \(profiles.count) profiles."

		return ([summary] + [missingPaletteNote(profiles), unavailableFontNote(profiles)].compactMap(\.self))
			.joined(separator: " ")
	}

	/// Worth saying out loud: several of Apple's bundled profiles set only a text and background
	/// color, so picking one changes less than the user might expect.
	private static func missingPaletteNote(_ profiles: [TerminalProfile]) -> String? {
		let names = profiles.filter { $0.ansi == nil }.map(\.name)
		guard !names.isEmpty else { return nil }

		let quoted = names.map { "“\($0)”" }.formatted(.list(type: .and))
		let verb = names.count == 1 ? "defines" : "define"
		return "\(quoted) \(verb) no ANSI colors, so the default palette is used for those."
	}

	/// Reported here rather than left to be noticed at selection: Terminal's profiles routinely
	/// name faces bundled inside Terminal.app, which this app cannot load, and silently keeping
	/// the current typeface would otherwise look like the font simply was not imported.
	private static func unavailableFontNote(_ profiles: [TerminalProfile]) -> String? {
		let affected = profiles.compactMap { profile -> (profile: String, font: String)? in
			guard let font = profile.font, !font.isAvailable else { return nil }
			return (profile.name, font.name)
		}
		guard let first = affected.first else { return nil }

		guard affected.count == 1 else {
			let quoted = affected.map { "“\($0.profile)”" }.formatted(.list(type: .and))
			return "\(quoted) use fonts that are not installed, "
				+ "so selecting them keeps your current typeface."
		}
		return "“\(first.profile)” uses \(first.font), which is not installed, "
			+ "so selecting it keeps your current typeface."
	}

	private static func tokenTestFailureMessage(for error: Error, provider: PullRequestProvider) -> String {
		switch error {
		case GitHostingError.missingToken:
			"Enter a token first."

		case GitHostingError.httpFailure(statusCode: 401):
			"HTTP 401 — the token is invalid, revoked, or expired."

		case GitHostingError.httpFailure(statusCode: 403):
			"HTTP 403 — the token lacks API access; check its scopes."

		case let GitHostingError.httpFailure(statusCode):
			"HTTP \(statusCode)."

		case GitHostingError.unauthenticated where provider == .gitlab:
			"GitLab accepted the request but returned no user. Fine-grained tokens cannot use the GraphQL API this app relies on — use a personal, project, or group token with the read_api scope."

		case GitHostingError.unauthenticated:
			"GitHub accepted the request but returned no user — the token likely cannot call the GraphQL API; check its type and permissions."

		default:
			error.localizedDescription
		}
	}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			// Tokens are trimmed because a paste often carries a trailing newline, which
			// corrupts the Bearer header and makes every request fail with a silent 401.
			case let .setYouTrackToken(token):
				state.$youtrackAuthToken.withLock { $0 = token.trimmingCharacters(in: .whitespacesAndNewlines) }
				state.youtrackTokenTest = .idle
				return .none

			case let .setGitHubToken(token):
				state.$githubToken.withLock { $0 = token.trimmingCharacters(in: .whitespacesAndNewlines) }
				// A verdict describes the token it was run against — a different token
				// must not inherit it.
				state.githubTokenTest = .idle
				return .none

			case let .setGitLabToken(token):
				state.$gitlabToken.withLock { $0 = token.trimmingCharacters(in: .whitespacesAndNewlines) }
				state.gitlabTokenTest = .idle
				return .none

			case .clearGitHubToken:
				state.$githubToken.withLock { $0 = "" }
				state.githubTokenTest = .idle
				return .none

			case .clearGitLabToken:
				state.$gitlabToken.withLock { $0 = "" }
				state.gitlabTokenTest = .idle
				return .none

			case .testYouTrackTokenButtonTapped:
				guard !state.youtrackAuthToken.isEmpty else {
					state.youtrackTokenTest = .failure(message: "Enter a token first.")
					return .none
				}
				let instances = Self.youTrackInstances(in: state)
				guard !instances.isEmpty else {
					state.youtrackTokenTest = .failure(
						message: "Set a YouTrack URL on a repository group (Repository Groups below) to test against."
					)
					return .none
				}
				state.youtrackTokenTest = .testing
				return .run { [token = state.youtrackAuthToken, youtrack] send in
					let results = await withTaskGroup(of: (Int, Result<String, any Error>).self) { group in
						for (index, instance) in instances.enumerated() {
							group.addTask {
								do {
									return try await (index, .success(youtrack.verifyToken(instance, token)))
								}
								catch {
									return (index, .failure(error))
								}
							}
						}
						var results: [(Int, Result<String, any Error>)] = []
						for await result in group {
							results.append(result)
						}
						return results.sorted { $0.0 < $1.0 }.map { (instance: instances[$0.0], result: $0.1) }
					}
					await send(.youTrackTokenTestFinished(Self.youTrackTokenTestOutcome(results)))
				}

			case let .youTrackTokenTestFinished(outcome):
				state.youtrackTokenTest = outcome
				return .none

			case .testGitHubTokenButtonTapped:
				state.githubTokenTest = .testing
				return .run { [token = state.githubToken, tokenVerification] send in
					await send(.gitHubTokenTestFinished(Self.tokenTestOutcome(provider: .github) {
						try await tokenVerification.verifyGitHubToken(token)
					}))
				}

			case .testGitLabTokenButtonTapped:
				state.gitlabTokenTest = .testing
				return .run { [token = state.gitlabToken, tokenVerification] send in
					await send(.gitLabTokenTestFinished(Self.tokenTestOutcome(provider: .gitlab) {
						try await tokenVerification.verifyGitLabToken(token)
					}))
				}

			case let .gitHubTokenTestFinished(outcome):
				state.githubTokenTest = outcome
				return .none

			case let .gitLabTokenTestFinished(outcome):
				state.gitlabTokenTest = outcome
				return .none

			case let .setPeriodicRefreshInterval(interval):
				state.$periodicRefreshInterval.withLock { $0 = interval }
				return .none

			case let .setGroupSupportsIOS(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].supportsIOS = value }
				return .none

			case let .setGroupSupportsAndroid(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].supportsAndroid = value }
				return .none

			case let .setGroupMobileSubfolderPath(groupId, path):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].mobileSubfolderPath = path }
				return .none

			case let .setGroupIOSSubfolderPath(groupId, path):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].iosSubfolderPath = path }
				return .none

			case let .setGroupSupportsTuist(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].supportsTuist = value }
				return .none

			case let .setGroupTicketIdRegex(groupId, regex):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].ticketIdRegex = regex }
				return .none

			case let .setGroupXcodeFilePreference(groupId, preference):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].xcodeFilePreference = preference }
				return .none

			case let .setGroupWorktreeCopyPaths(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].worktreeCopyPaths = value }
				return .none

			case let .setGroupSupportsWeb(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].supportsWeb = value }
				return .none

			case let .setGroupWebIndexPath(groupId, path):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].webIndexPath = path }
				return .none

			case let .setGroupDefaultBranch(groupId, value):
				// Trim so a whitespace-only entry is stored as empty (= master/main fallback),
				// keeping every downstream consumer (resolver, merge, alerts) consistent.
				let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].defaultBranch = trimmed }
				return .none

			case let .setGroupYouTrackBaseURL(groupId, value):
				// Whitespace-trim only; trailing slashes and a pasted "/api" suffix are handled at
				// consumption by YouTrackURLBuilder — stripping "/" here would fight the
				// per-keystroke TextField binding (typing "https://" would collapse).
				let trimmedURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].youtrackBaseURL = trimmedURL }
				// The verdict names the instances it ran against; a changed URL is a different one.
				state.youtrackTokenTest = .idle
				return .none

			case let .setGroupTerminalStartupCommand(groupId, value):
				// Stored untrimmed: the TextField binding writes on every keystroke, and trimming
				// here would eat the space typed between words. Consumers trim.
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].terminalStartupCommand = value }
				return .none

			case let .setGroupDefaultWorktreeSource(groupId, source):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].defaultWorktreeSource = source }
				return .none

			case let .setGroupSkipGlobalTerminalStartupCommand(groupId, value):
				state.$groupSettings.withLock {
					$0[groupId, default: RepoGroupSettings()].skipGlobalTerminalStartupCommand = value
				}
				return .none

			case let .setBranchNameRegex(regex):
				state.$branchNameRegex.withLock { $0 = regex }
				return .none

			case let .setTicketBranchNameTemplate(template):
				state.$ticketBranchNameTemplate.withLock { $0 = template }
				return .none

			case let .setOpenXcodeAfterGenerate(shouldOpen):
				state.$openXcodeAfterGenerate.withLock { $0 = shouldOpen }
				return .none

			case let .setDeleteDerivedDataOnWorktreeDelete(value):
				state.$deleteDerivedDataOnWorktreeDelete.withLock { $0 = value }
				return .none

			case let .setTuistCacheType(cacheType):
				state.$tuistCacheType.withLock { $0 = cacheType }
				return .none

			case let .setTerminalApp(app):
				state.$terminalApp.withLock { $0 = app }
				return .none

			case let .setTerminalOpeningBehavior(behavior):
				state.$terminalOpeningBehavior.withLock { $0 = behavior }
				return .none

			case let .setClaudeCodeOpeningBehavior(behavior):
				state.$claudeCodeOpeningBehavior.withLock { $0 = behavior }
				return .none

			case let .setAndroidStudioPath(path):
				state.$androidStudioPath.withLock { $0 = path }
				return .none

			case let .setWorktreeBasePath(path):
				state.$worktreeBasePath.withLock { $0 = path }
				return .none

			case let .setMisePath(path):
				state.$misePath.withLock { $0 = path }
				return .none

			case let .setTuistRunMode(mode):
				state.$tuistRunMode.withLock { $0 = mode }
				return .none

			case let .setTerminalColorTheme(theme):
				state.$terminalColorTheme.withLock { $0 = theme }
				Self.adoptProfileFont(for: theme, in: &state)
				return .none

			case let .setTerminalCopyOnSelect(value):
				state.$terminalCopyOnSelect.withLock { $0 = value }
				return .none

			case let .setTerminalMouseReporting(value):
				state.$terminalMouseReporting.withLock { $0 = value }
				return .none

			case let .setTerminalStartupCommand(value):
				// Stored untrimmed for the same reason as the group command: consumers trim.
				state.$terminalStartupCommand.withLock { $0 = value }
				return .none

			case let .setTerminalStartupCommandInNewTabs(value):
				state.$terminalStartupCommandInNewTabs.withLock { $0 = value }
				return .none

			case let .setTerminalNotifications(value):
				state.$terminalNotifications.withLock { $0 = value }
				return .none

			case let .setTerminalClaudeStatusDetection(value):
				state.$terminalClaudeStatusDetection.withLock { $0 = value }
				return .none

			case let .setTerminalFontSize(size):
				state.$terminalFontSize.withLock { $0 = TerminalFontSize.clamped(size) }
				return .none

			case let .setTerminalFontName(name):
				// Stored even if the font cannot be resolved right now; `TerminalFontFamily.resolve`
				// falls back to the system face, so a name that stops resolving degrades rather
				// than leaving the terminal with no font.
				state.$terminalFontName.withLock { $0 = name }
				return .none

			case let .setUIFontSize(size):
				state.$uiFontSize.withLock { $0 = UIFontSize.clamped(size) }
				return .none

			case .importFromTerminalAppButtonTapped:
				return .run { [profileImport] send in
					do {
						await send(.profilesImported(try await profileImport.importFromTerminalApp()))
					}
					catch {
						await send(.profileImportFailed(message: Self.importFailureMessage(error)))
					}
				}

			case let .profileFilesSelected(urls):
				return .run { [profileImport] send in
					var imported: [TerminalProfile] = []
					// One bad file does not abandon the rest of a multi-file selection; the
					// first failure is reported once everything importable is in.
					var failure: String?
					for url in urls {
						do {
							imported.append(contentsOf: try await profileImport.importFromFile(url))
						}
						catch {
							failure = failure ?? Self.importFailureMessage(error)
						}
					}
					if !imported.isEmpty {
						await send(.profilesImported(imported))
					}
					if let failure {
						await send(.profileImportFailed(message: failure))
					}
				}

			case let .profilesImported(profiles):
				state.$terminalProfiles.withLock { $0 = Self.merge(profiles, into: $0) }
				state.alert = AlertState {
					TextState("Profiles Imported")
				} actions: {
					ButtonState(role: .cancel) { TextState("OK") }
				} message: {
					TextState(Self.importSuccessMessage(profiles))
				}
				return .none

			case let .profileImportFailed(message):
				state.alert = AlertState {
					TextState("Import Failed")
				} actions: {
					ButtonState(role: .cancel) { TextState("OK") }
				} message: {
					TextState(message)
				}
				return .none

			case let .deleteProfileButtonTapped(name):
				state.$terminalProfiles.withLock { $0.removeAll { $0.name == name } }
				// Leaving the selection pointing at a deleted profile would still render (it
				// falls back), but the picker would show nothing selected.
				if state.terminalColorTheme == .imported(name: name) {
					state.$terminalColorTheme.withLock { $0 = .builtIn(.basicDark) }
				}
				return .none

			case .clearTokenButtonTapped:
				state.alert = AlertState {
					TextState("Clear Token")
				} actions: {
					ButtonState(role: .destructive, action: .confirmClearToken) {
						TextState("Clear")
					}
					ButtonState(role: .cancel) {
						TextState("Cancel")
					}
				} message: {
					TextState(
						"Are you sure you want to clear the token? YouTrack features will not work without a valid token."
					)
				}
				return .none

			case .alert(.presented(.confirmClearToken)):
				state.$youtrackAuthToken.withLock { $0 = "" }
				state.youtrackTokenTest = .idle
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
