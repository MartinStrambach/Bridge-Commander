import ComposableArchitecture
import Foundation
import Testing
import ToolsIntegration
@testable import Settings

@Suite("SettingsBackup file format")
struct SettingsBackupFormatTests {
	@Test("a backup reads back as written")
	func roundTrip() throws {
		var backup = SettingsBackup()
		backup.exportedAt = Date(timeIntervalSince1970: 1_800_000_000)
		backup.githubToken = "ghp_token"
		backup.uiFontSize = 15
		backup.periodicRefreshInterval = PeriodicRefreshInterval.tenMinutes.rawValue
		backup.repositoryRowLayout = .default
		backup.trackedRepoPaths = ["/repos/app"]
		backup.groupSettings = ["/repos/app": RepoGroupSettings(defaultBranch: "develop")]
		backup.terminalProfiles = [.fixture(name: "Ocean", ansi: TerminalProfile.fixtureAnsi())]
		backup.fileOpenApplications = ["kt": "com.google.android.studio"]

		#expect(try SettingsBackup.decoded(from: backup.encoded()) == backup)
	}

	@Test("JSON without a format version is not taken for a backup")
	func rejectsOtherJSON() {
		#expect(throws: SettingsBackupError.notASettingsBackup) {
			try SettingsBackup.decoded(from: Data(#"{"uiFontSize": 15}"#.utf8))
		}
		#expect(throws: SettingsBackupError.notASettingsBackup) {
			try SettingsBackup.decoded(from: Data("not json".utf8))
		}
	}

	@Test("settings a newer version wrote are ignored, the known ones still read")
	func ignoresUnknownKeys() throws {
		let json = #"{"formatVersion": 2, "someFutureSetting": true, "terminalCopyOnSelect": true}"#
		let backup = try SettingsBackup.decoded(from: Data(json.utf8))
		#expect(backup.formatVersion == 2)
		#expect(backup.terminalCopyOnSelect == true)
		#expect(backup.uiFontSize == nil)
	}

	@Test("repository paths are standardized and deduplicated on read")
	func standardizesPaths() throws {
		let json = #"""
		{"formatVersion": 1,
		 "trackedRepoPaths": ["/repos/app/", "/repos/./app", "/repos/web"],
		 "groupSettings": {"/repos/app/": {"defaultBranch": "develop"}}}
		"""#
		let backup = try SettingsBackup.decoded(from: Data(json.utf8))
		#expect(backup.trackedRepoPaths == ["/repos/app", "/repos/web"])
		#expect(backup.groupSettings == ["/repos/app": RepoGroupSettings(defaultBranch: "develop")])
	}

	@Test("a group setting value this version does not know does not fail the import")
	func toleratesUnknownGroupValues() throws {
		let json = #"""
		{"formatVersion": 1,
		 "groupSettings": {"/repos/app": {"defaultBranch": "develop", "xcodeFilePreference": "someFutureChoice"}}}
		"""#
		let backup = try SettingsBackup.decoded(from: Data(json.utf8))
		#expect(backup.groupSettings?["/repos/app"] == RepoGroupSettings(defaultBranch: "develop"))
	}

	@Test("a backup written before the macOS toggle imports its iOS groups unchanged")
	func importsBackupFromBeforeMacOSToggle() throws {
		let json = #"""
		{"formatVersion": 1,
		 "groupSettings": {"/repos/app": {"supportsIOS": true, "supportsTuist": true, "iosSubfolderPath": "ios"}}}
		"""#
		let backup = try SettingsBackup.decoded(from: Data(json.utf8))
		#expect(backup.groupSettings?["/repos/app"] == RepoGroupSettings(
			supportsIOS: true,
			iosSubfolderPath: "ios",
			supportsTuist: true
		))
	}

	@Test("a macOS group survives export and import")
	func macOSGroupRoundTrip() throws {
		var backup = SettingsBackup()
		backup.groupSettings = [
			"/repos/mac": RepoGroupSettings(supportsMacOS: true, iosSubfolderPath: "App", supportsTuist: true),
		]
		#expect(try SettingsBackup.decoded(from: backup.encoded()).groupSettings == backup.groupSettings)
	}

	@Test("a startup command with line breaks or control characters refuses the whole file")
	func rejectsMultilineCommands() throws {
		for json in [
			#"{"formatVersion": 1, "terminalStartupCommand": "claude\nrm -rf ~"}"#,
			#"{"formatVersion": 1, "groupSettings": {"/repos/app": {"terminalStartupCommand": "ls\u001b[2J"}}}"#,
		] {
			#expect(throws: SettingsBackupError.unsafeStartupCommand) {
				try SettingsBackup.decoded(from: Data(json.utf8))
			}
		}
		let fine = #"{"formatVersion": 1, "terminalStartupCommand": "mise exec -- claude"}"#
		#expect(try SettingsBackup.decoded(from: Data(fine.utf8)).terminalStartupCommand == "mise exec -- claude")
	}

	@Test("tokens count as included only when the file carries one")
	func includesTokens() {
		var backup = SettingsBackup()
		#expect(!backup.includesTokens)
		backup.gitlabToken = ""
		#expect(backup.includesTokens)
	}
}

@MainActor
@Suite("SettingsReducer settings export and import")
struct SettingsReducerBackupTests {
	private static let exportDate = Date(timeIntervalSince1970: 1_800_000_000)

	private static func document(for state: SettingsReducer.State, includingTokens: Bool) throws -> SettingsBackupDocument {
		try SettingsBackupDocument(
			data: SettingsBackup(state: state, includesTokens: includingTokens, exportedAt: exportDate).encoded(),
			filename: SettingsBackup.defaultFilename(exportedAt: exportDate)
		)
	}

	// MARK: - Export

	@Test("without tokens set, export goes straight to the save panel")
	func exportWithoutTokens() async throws {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0.date.now = Self.exportDate
		}

		await store.send(.exportSettingsButtonTapped) {
			$0.exportedSettings = try? Self.document(for: $0, includingTokens: false)
		}
		await store.send(.settingsExportDismissed) {
			$0.exportedSettings = nil
		}
	}

	@Test("with a token set, export asks first, and the answer decides whether tokens are written")
	func exportAsksAboutTokens() async throws {
		let state = SettingsReducer.State()
		state.$githubToken.withLock { $0 = "ghp_secret" }
		let store = TestStore(initialState: state) {
			SettingsReducer()
		} withDependencies: {
			$0.date.now = Self.exportDate
		}

		await store.send(.exportSettingsButtonTapped) {
			$0.alert = SettingsReducer.exportTokensAlert
		}
		await store.send(.alert(.presented(.exportSettings(includingTokens: false)))) {
			$0.alert = nil
			$0.exportedSettings = try? Self.document(for: $0, includingTokens: false)
		}

		let exported = try SettingsBackup.decoded(from: #require(store.state.exportedSettings).data)
		#expect(exported.githubToken == nil)
		#expect(!exported.includesTokens)

		await store.send(.settingsExportDismissed) {
			$0.exportedSettings = nil
		}
		await store.send(.exportSettingsButtonTapped) {
			$0.alert = SettingsReducer.exportTokensAlert
		}
		await store.send(.alert(.presented(.exportSettings(includingTokens: true)))) {
			$0.alert = nil
			$0.exportedSettings = try? Self.document(for: $0, includingTokens: true)
		}
		let withTokens = try SettingsBackup.decoded(from: #require(store.state.exportedSettings).data)
		#expect(withTokens.githubToken == "ghp_secret")
	}

	// MARK: - Import

	@Test("a picked file is read and the import is confirmed before anything changes; repositories not on this Mac are left out")
	func importAsksForConfirmation() async throws {
		var backup = SettingsBackup()
		backup.terminalCopyOnSelect = true
		backup.trackedRepoPaths = ["/repos/app", "/elsewhere/web"]
		let data = try backup.encoded()
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[SettingsBackupClient.self].readFile = { _ in data }
			$0[SettingsBackupClient.self].missingDirectories = { paths in paths.filter { $0.hasPrefix("/elsewhere") } }
		}

		var loaded = backup
		loaded.trackedRepoPaths = ["/repos/app"]
		await store.send(.settingsFileSelected(URL(filePath: "/tmp/settings.json")))
		await store.receive(\.settingsFileLoaded) {
			$0.alert = SettingsReducer.importSettingsAlert(
				loaded,
				skippedRepositoryPaths: ["/elsewhere/web"],
				current: $0
			)
		}
		#expect(store.state.alert.map { String(state: $0.message ?? TextState("")) }?.contains("/elsewhere/web") == true)
	}

	@Test("the confirmation lists commands the file would change, and only those")
	func importListsChangedCommands() async {
		let state = SettingsReducer.State()
		state.$terminalStartupCommand.withLock { $0 = "claude" }
		state.$groupSettings.withLock {
			$0 = ["/repos/app": RepoGroupSettings(terminalStartupCommand: "make dev")]
		}

		var backup = SettingsBackup()
		backup.terminalStartupCommand = "claude"
		backup.misePath = "/tmp/evil"
		backup.groupSettings = [
			"/repos/app": RepoGroupSettings(terminalStartupCommand: "make dev"),
			"/repos/web": RepoGroupSettings(terminalStartupCommand: "curl x | sh"),
		]

		#expect(backup.commandsChanged(from: state) == [
			"Startup command for /repos/web: curl x | sh",
			"mise executable: /tmp/evil",
		])
	}

	@Test("a file that is not a backup reports why")
	func importRejectsOtherFiles() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[SettingsBackupClient.self].readFile = { _ in Data("[]".utf8) }
		}

		await store.send(.settingsFileSelected(URL(filePath: "/tmp/settings.json")))
		let message = SettingsBackupError.notASettingsBackup.errorDescription ?? ""
		await store.receive(\.settingsImportFailed, message) {
			$0.alert = AlertState {
				TextState("Import Failed")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState(message)
			}
		}
	}

	@Test("confirming replaces plain settings and merges repositories, groups and profiles")
	func importAppliesBackup() async {
		var state = SettingsReducer.State()
		state.$trackedRepoPaths.withLock { $0 = ["/repos/app"] }
		state.$groupSettings.withLock {
			$0 = [
				"/repos/app": RepoGroupSettings(defaultBranch: "main"),
				"/repos/web": RepoGroupSettings(defaultBranch: "trunk"),
			]
		}
		state.$terminalProfiles.withLock { $0 = [.fixture(name: "Basic")] }
		state.$githubToken.withLock { $0 = "ghp_old" }
		state.githubTokenTest = .success(username: "someone")

		var backup = SettingsBackup()
		backup.githubToken = " ghp_new\n"
		backup.uiFontSize = 99
		backup.terminalApp = "noSuchTerminal"
		backup.tuistCacheType = TuistCacheType.allCases.last?.rawValue
		backup.trackedRepoPaths = ["/repos/api", "/repos/app"]
		backup.groupSettings = [
			"/repos/app": RepoGroupSettings(defaultBranch: "develop"),
			"/repos/api": RepoGroupSettings(defaultBranch: "main"),
		]
		backup.terminalProfiles = [.fixture(name: "Ocean")]
		backup.terminalColorTheme = TerminalThemeSelection.imported(name: "Ocean").rawValue

		state.alert = SettingsReducer.importSettingsAlert(backup, skippedRepositoryPaths: [], current: state)
		let store = TestStore(initialState: state) {
			SettingsReducer()
		}

		await store.send(.alert(.presented(.confirmImportSettings(backup)))) {
			$0.$githubToken.withLock { $0 = "ghp_new" }
			$0.githubTokenTest = .idle
			$0.$uiFontSize.withLock { $0 = UIFontSize.maximum }
			// An unknown terminal app is skipped rather than reset.
			$0.$tuistCacheType.withLock { $0 = TuistCacheType.allCases.last! }
			$0.$trackedRepoPaths.withLock { $0 = ["/repos/app", "/repos/api"] }
			$0.$groupSettings.withLock {
				$0 = [
					"/repos/app": RepoGroupSettings(defaultBranch: "develop"),
					"/repos/api": RepoGroupSettings(defaultBranch: "main"),
					"/repos/web": RepoGroupSettings(defaultBranch: "trunk"),
				]
			}
			$0.$terminalProfiles.withLock { $0 = [.fixture(name: "Basic"), .fixture(name: "Ocean")] }
			$0.$terminalColorTheme.withLock { $0 = .imported(name: "Ocean") }
			$0.alert = AlertState {
				TextState("Settings Imported")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState("Repositories added by the import appear after the next refresh (⌘R).")
			}
		}
	}
}
