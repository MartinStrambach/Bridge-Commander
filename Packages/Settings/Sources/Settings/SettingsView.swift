import AppUI
import AppKit
import ComposableArchitecture
import GitHosting
import SwiftUI
import ToolsIntegration
import UniformTypeIdentifiers

/// `.terminal` has no registered system type, so it is built from the extension; the
/// property-list type is allowed alongside it because that is what the files actually are.
/// At file scope because `SettingsView` is generic, and generic types have no static storage.
private let terminalProfileContentTypes: [UTType] = [
	UTType(filenameExtension: "terminal"),
	.propertyList,
]
.compactMap(\.self)

/// Enumerating installed fonts touches the font server, so it happens once per process (globals
/// are initialized lazily, once) rather than on every body evaluation.
private let installedMonospacedFamilies = TerminalFontFamily.availableMonospacedFamilies()

/// `Updates` is the Updates section's controls, supplied by the app target: the updater is
/// Sparkle's, and this package stays free of a Sparkle dependency.
public struct SettingsView<Updates: View>: View {
	@Bindable
	public var store: StoreOf<SettingsReducer>

	private let updates: Updates

	@State
	private var isImportingProfileFiles = false

	/// Groups start collapsed each time Settings opens, so a long list of groups stays scannable.
	@State
	private var expandedGroupIds: Set<String> = []

	public init(store: StoreOf<SettingsReducer>, @ViewBuilder updates: () -> Updates) {
		self.store = store
		self.updates = updates()
	}

	public var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				Text("Settings")
					.scaledFont(.title2)
					.fontWeight(.bold)

				Divider()

				appearanceSection
				youtrackAuthenticationSection
				gitHubAuthenticationSection
				gitLabAuthenticationSection
				repositoryRefreshSection
				branchNameRegexSection
				HStack(alignment: .top) {
					tuistCacheOptionsSection
					tuistGenerateOptionsSection
				}
				tuistExecutionSection
				HStack(alignment: .top) {
					terminalBehaviorSection
					claudeCodeBehaviorSection
				}
				terminalColorThemeSection
				builtInTerminalSection
				androidStudioPathSection
				worktreeOptionsSection
				repositoryGroupsSection
				updatesSection
			}
			.padding()
		}
		.frame(minWidth: 500, idealWidth: 600, minHeight: 600, idealHeight: 800)
		.alert($store.scope(\.$alert, action: \.alert))
	}

	private var appearanceSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Appearance")
				.scaledFont(.headline)

			HStack(spacing: 8) {
				Stepper(
					value: $store.uiFontSize.sending(\.setUIFontSize),
					in: UIFontSize.minimum ... UIFontSize.maximum,
					step: UIFontSize.step
				) {
					Text("Text size: \(Int(store.uiFontSize)) pt")
				}

				Button("Reset") {
					store.send(.setUIFontSize(UIFontSize.default))
				}
				.buttonStyle(.scaledAutomatic)
				.disabled(store.uiFontSize == UIFontSize.default)
			}

			Text(
				"Size of body text across the app; headlines, captions and diffs scale with it. The built-in terminal has its own font size below. Default: \(Int(UIFontSize.default)) pt."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var terminalBehaviorSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Terminal")
				.scaledFont(.headline)

			Text("Choose which terminal app opens when clicking the Terminal button.")
				.scaledFont(.caption)
				.foregroundColor(.secondary)

			Picker(
				"Terminal App",
				selection: $store.terminalApp.sending(\.setTerminalApp)
			) {
				ForEach(TerminalApp.allCases, id: \.self) { app in
					Text(app.displayName).tag(app)
				}
			}
			.pickerStyle(.segmented)

			if store.terminalApp.supportsBehaviorSelection {
				Picker(
					"Opening Behavior",
					selection: $store.terminalOpeningBehavior.sending(\.setTerminalOpeningBehavior)
				) {
					ForEach(TerminalOpeningBehavior.allCases, id: \.self) { behavior in
						Text(behavior.displayName).tag(behavior)
					}
				}
				.pickerStyle(.segmented)
			}
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var claudeCodeBehaviorSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Claude Code Opening Behavior")
				.scaledFont(.headline)

			Text("Choose how Claude Code should open when clicking the Claude Code button.")
				.scaledFont(.caption)
				.foregroundColor(.secondary)

			Picker(
				"Opening Behavior",
				selection: $store.claudeCodeOpeningBehavior.sending(\.setClaudeCodeOpeningBehavior)
			) {
				ForEach(TerminalOpeningBehavior.allCases, id: \.self) { behavior in
					Text(behavior.displayName).tag(behavior)
				}
			}
			.pickerStyle(.segmented)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var terminalColorThemeSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Terminal Color Theme")
				.scaledFont(.headline)

			Text("Choose the color theme for the built-in terminal. Applies to newly opened terminals.")
				.scaledFont(.caption)
				.foregroundColor(.secondary)

			Picker(
				"Color Theme",
				selection: $store.terminalColorTheme.sending(\.setTerminalColorTheme)
			) {
				Section("Built-in") {
					ForEach(TerminalColorTheme.allCases, id: \.self) { theme in
						Text(theme.displayName).tag(TerminalThemeSelection.builtIn(theme))
					}
				}
				if !store.terminalProfiles.isEmpty {
					Section("Imported") {
						ForEach(store.terminalProfiles) { profile in
							Text(profile.name).tag(TerminalThemeSelection.imported(name: profile.name))
						}
					}
				}
			}
			.pickerStyle(.menu)

			Divider()
				.padding(.vertical, 2)

			Text("Import Terminal.app Profiles")
				.scaledFont(.subheadline)
				.fontWeight(.semibold)

			Text(
				"Bring in the color schemes from Terminal.app, or from a .terminal file exported via Terminal → Settings → Profiles → Export. A profile that defines no ANSI colors keeps the default palette."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			HStack(spacing: 8) {
				Button {
					store.send(.importFromTerminalAppButtonTapped)
				} label: {
					Label("Import from Terminal.app", systemImage: "square.and.arrow.down.on.square")
				}
				.buttonStyle(.scaledBordered)

				Button {
					isImportingProfileFiles = true
				} label: {
					Label("Import File…", systemImage: "folder")
				}
				.buttonStyle(.scaledBordered)
			}

			if !store.terminalProfiles.isEmpty {
				VStack(alignment: .leading, spacing: 6) {
					ForEach(store.terminalProfiles) { profile in
						importedProfileRow(profile)
					}
				}
				.padding(.top, 4)
			}
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
		.fileImporter(
			isPresented: $isImportingProfileFiles,
			allowedContentTypes: terminalProfileContentTypes,
			allowsMultipleSelection: true
		) { result in
			switch result {
			case let .success(urls):
				store.send(.profileFilesSelected(urls))

			case let .failure(error):
				store.send(.profileImportFailed(message: error.localizedDescription))
			}
		}
	}

	private func importedProfileRow(_ profile: TerminalProfile) -> some View {
		HStack(spacing: 8) {
			profileSwatch(profile)

			Text(profile.name)
				.scaledFont(.caption)

			if profile.ansi == nil {
				Text("default palette")
					.scaledFont(.caption2)
					.foregroundColor(.secondary)
					.help("This profile defines no ANSI colors, so the default 16-color palette is used.")
			}

			if let font = profile.font {
				profileFontBadge(font)
			}

			Spacer()

			Button {
				store.send(.deleteProfileButtonTapped(name: profile.name))
			} label: {
				Image(systemName: "minus.circle")
			}
			.buttonStyle(.borderless)
			.help("Remove profile")
		}
	}

	/// The profile's typeface, struck through when it is not installed — Terminal's own profiles
	/// name faces bundled inside Terminal.app, so this is a common state and not an error.
	private func profileFontBadge(_ font: TerminalProfileFont) -> some View {
		let available = font.isAvailable
		return Text("\(font.name) \(Int(font.size))pt")
			.scaledFont(.caption2)
			.foregroundColor(.secondary)
			.strikethrough(!available)
			.help(
				available
					? "Selecting this profile also switches the terminal to this font."
					: "This font is not installed, so selecting this profile applies the size but keeps your current typeface."
			)
	}

	/// Background, foreground and — when the profile has one — its ANSI palette, so the list is
	/// scannable without applying each theme in turn.
	private func profileSwatch(_ profile: TerminalProfile) -> some View {
		HStack(spacing: 1) {
			if let ansi = profile.ansi {
				ForEach(Array(ansi.enumerated()), id: \.offset) { _, color in
					Rectangle()
						.fill(Color(color.nsColor))
						.frame(width: 5, height: 14)
				}
			}
			else {
				// Without a palette there would be nothing but padding to look at, so show the
				// text color against the background — which is all this profile actually sets.
				Text("Aa")
					.scaledFont(size: 10, design: .monospaced)
					.foregroundColor(Color(profile.foreground.nsColor))
					.frame(width: 94, height: 14)
			}
		}
		.padding(2)
		.background(Color(profile.background.nsColor))
		.overlay(
			RoundedRectangle(cornerRadius: 3)
				.stroke(Color(profile.foreground.nsColor).opacity(0.5), lineWidth: 1)
		)
		.clipShape(RoundedRectangle(cornerRadius: 3))
		.frame(width: 100, alignment: .leading)
	}

	/// A stored name that no longer resolves is appended, so the picker still shows what is
	/// configured instead of silently rewriting it to the default.
	private var monospacedFontFamilies: [String] {
		let installed = installedMonospacedFamilies
		let selected = store.terminalFontName
		guard !selected.isEmpty, !installed.contains(selected) else { return installed }
		return installed + [selected]
	}

	private var builtInTerminalSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Built-in Terminal")
				.scaledFont(.headline)

			Picker(
				"Font:",
				selection: $store.terminalFontName.sending(\.setTerminalFontName)
			) {
				Text(TerminalFontFamily.systemDefaultDisplayName)
					.tag(TerminalFontFamily.systemDefault)
				Divider()
				ForEach(monospacedFontFamilies, id: \.self) { family in
					Text(family)
						.font(.custom(family, size: NSFont.systemFontSize))
						.tag(family)
				}
			}
			.frame(maxWidth: 320)

			Text(
				"Only monospaced fonts are listed — a proportional face would break the terminal's character grid."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			HStack(spacing: 8) {
				Stepper(
					value: $store.terminalFontSize.sending(\.setTerminalFontSize),
					in: TerminalFontSize.minimum ... TerminalFontSize.maximum,
					step: TerminalFontSize.step
				) {
					Text("Font size: \(Int(store.terminalFontSize)) pt")
				}

				// A sample rather than a live preview of a pane: the font and its size are what
				// change, and seeing them is enough to pick without applying first.
				Text("Aa")
					.font(
						Font(
							TerminalFontFamily.resolve(
								name: store.terminalFontName,
								size: store.terminalFontSize
							)
						)
					)
					.foregroundColor(.secondary)
					.frame(minWidth: 40, alignment: .leading)
			}

			Text(
				"Applies to open terminals right away. Also available as ⌘+ and ⌘− while a terminal is focused, with ⌘0 back to \(Int(TerminalFontSize.default)) pt."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			Toggle(
				"Copy selected text automatically",
				isOn: $store.terminalCopyOnSelect.sending(\.setTerminalCopyOnSelect)
			)

			Text(
				"Highlighting text with the mouse puts it on the clipboard right away, which replaces whatever you copied elsewhere. With this off, use ⌘C to copy the selection."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			Toggle(
				"Send mouse events to terminal apps",
				isOn: $store.terminalMouseReporting.sending(\.setTerminalMouseReporting)
			)

			Text(
				"Programs like lazygit and vim can then see clicks and the scroll wheel, so scrolling affects the pane under the pointer instead of the focused one. With this off they never get the pointer position. Hold ⇧ while dragging to select text either way."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			HStack {
				Text("Startup command:")
				TextField("Run in each new built-in terminal (empty = none)", text: Binding(
					get: { store.terminalStartupCommand },
					set: { store.send(.setTerminalStartupCommand($0)) }
				))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)
			}

			Text(
				"Typed into a repository's first built-in terminal tab once its shell is ready. A repository group's own Terminal Command replaces it for that group's tabs."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			Toggle(
				"Also run the startup command in new tabs",
				isOn: $store.terminalStartupCommandInNewTabs.sending(\.setTerminalStartupCommandInNewTabs)
			)

			Text(
				"With this off, tabs opened with + or ⌘T start with a plain shell."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			Toggle(
				"Show notifications from terminal tabs",
				isOn: $store.terminalNotifications.sending(\.setTerminalNotifications)
			)

			Text(
				"Posts a notification when Claude Code in a built-in terminal tab you are not looking at needs a response, or when a program asks for one (OSC 9 / OSC 777, as in Ghostty). Click it to open that tab. For Claude's own permission notifications, set its notification channel to Ghostty in /config."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			Picker(
				"Detect Claude waiting from:",
				selection: $store.terminalClaudeStatusDetection.sending(\.setTerminalClaudeStatusDetection)
			) {
				ForEach(ClaudeStatusDetection.allCases, id: \.self) { detection in
					Text(detection.displayName).tag(detection)
				}
			}
			.frame(maxWidth: 420)

			Text("\(store.terminalClaudeStatusDetection.explanation) Applies to terminals opened after the change.")
				.scaledFont(.caption)
				.foregroundColor(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var youtrackAuthenticationSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("YouTrack Authentication")
				.scaledFont(.headline)

			Text(
				"Enter your YouTrack personal access token. This token will be stored locally and used to fetch issue details."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			SecureField("YouTrack Auth Token", text: $store.youtrackAuthToken.sending(\.setYouTrackToken))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)

			HStack(spacing: 8) {
				Button(action: { store.send(.clearTokenButtonTapped) }) {
					Label("Clear Token", systemImage: "xmark.circle")
				}
				.buttonStyle(.scaledBordered)
				.foregroundColor(.red)

				Button(action: { store.send(.testYouTrackTokenButtonTapped) }) {
					Label("Test Connection", systemImage: "checkmark.shield")
				}
				.buttonStyle(.scaledBordered)
				.disabled(store.youtrackTokenTest == .testing)
			}

			tokenTestResult(store.youtrackTokenTest)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var gitHubAuthenticationSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("GitHub Authentication")
				.scaledFont(.headline)

			Text(
				"Enter a GitHub personal access token. Fine-grained: grant the repository permission \"Pull requests: Read-only\" (Metadata is added automatically). Classic: `repo` scope. Used to detect open PRs for the current branch."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			SecureField("GitHub Token", text: $store.githubToken.sending(\.setGitHubToken))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)

			HStack(spacing: 8) {
				Button(action: { store.send(.clearGitHubToken) }) {
					Label("Clear Token", systemImage: "xmark.circle")
				}
				.buttonStyle(.scaledBordered)
				.foregroundColor(.red)

				Button(action: { store.send(.testGitHubTokenButtonTapped) }) {
					Label("Test Connection", systemImage: "checkmark.shield")
				}
				.buttonStyle(.scaledBordered)
				.disabled(store.githubTokenTest == .testing)
			}

			tokenTestResult(store.githubTokenTest)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var gitLabAuthenticationSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("GitLab Authentication")
				.scaledFont(.headline)

			Text(
				"Enter a GitLab access token (personal, project, or group) with the `read_api` scope. Fine-grained tokens are not supported — the app uses GitLab's GraphQL API, which they cannot access yet. Used to detect open merge requests for the current branch."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			SecureField("GitLab Token", text: $store.gitlabToken.sending(\.setGitLabToken))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)

			HStack(spacing: 8) {
				Button(action: { store.send(.clearGitLabToken) }) {
					Label("Clear Token", systemImage: "xmark.circle")
				}
				.buttonStyle(.scaledBordered)
				.foregroundColor(.red)

				Button(action: { store.send(.testGitLabTokenButtonTapped) }) {
					Label("Test Connection", systemImage: "checkmark.shield")
				}
				.buttonStyle(.scaledBordered)
				.disabled(store.gitlabTokenTest == .testing)
			}

			tokenTestResult(store.gitlabTokenTest)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	/// Inline verdict shown under a token's buttons. Idle renders nothing so the
	/// section keeps its compact height until a test has actually run.
	@ViewBuilder
	private func tokenTestResult(_ test: TokenTestState) -> some View {
		switch test {
		case .idle:
			EmptyView()

		case .testing:
			HStack(spacing: 6) {
				ProgressView()
					.controlSize(.small)
				Text("Testing…")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
			}

		case let .success(username):
			HStack(spacing: 6) {
				Image(systemName: "checkmark.circle.fill")
					.foregroundColor(.green)
				Text("Authenticated as \(username)")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
			}

		case let .failure(message):
			HStack(alignment: .firstTextBaseline, spacing: 6) {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundColor(.orange)
				Text(message)
					.scaledFont(.caption)
					.foregroundColor(.secondary)
					.textSelection(.enabled)
			}
		}
	}

	private var updatesSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Updates")
				.scaledFont(.headline)

			updates
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var repositoryRefreshSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Repository Refresh")
				.scaledFont(.headline)

			Text("Automatically refresh repository status at the selected interval.")
				.scaledFont(.caption)
				.foregroundColor(.secondary)

			Picker(
				"Refresh Interval",
				selection: $store.periodicRefreshInterval.sending(\.setPeriodicRefreshInterval)
			) {
				ForEach(PeriodicRefreshInterval.allCases, id: \.self) { interval in
					Text(interval.displayName).tag(interval)
				}
			}
			.pickerStyle(.segmented)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var branchNameRegexSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Branch Name Regex Pattern")
				.scaledFont(.headline)

			Text(
				"Specify the regular expression pattern to remove project prefixes from branch names (e.g., '[a-zA-Z]+-\\\\d+[_/]' matches 'MOB-123_' or 'tech-60/')."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			TextField("Branch Name Regex", text: $store.branchNameRegex.sending(\.setBranchNameRegex))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)

			Text("Branch Name for Ticket Worktrees")
				.scaledFont(.headline)
				.padding(.top, 8)

			Text(
				"Used when a worktree is created from a YouTrack ticket. {ticket} is the ticket ID, {summary} its summary as lowercase_words (e.g. 'bugfix/{summary}_{ticket}'). The name can still be edited before creating."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			TextField(
				BranchNameFormatter.defaultTicketBranchTemplate,
				text: $store.ticketBranchNameTemplate.sending(\.setTicketBranchNameTemplate)
			)
			.textFieldStyle(.roundedBorder)
			.scaledFont(.body, design: .monospaced)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var tuistGenerateOptionsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Tuist Generate Options")
				.scaledFont(.headline)

			Toggle(
				"Open Xcode after generating project",
				isOn: $store.openXcodeAfterGenerate.sending(\.setOpenXcodeAfterGenerate)
			)

			Text(
				"Automatically open the generated Xcode project after running 'tuist generate'."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var tuistCacheOptionsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Tuist Cache Options")
				.scaledFont(.headline)

			Picker(
				"Cache Type",
				selection: $store.tuistCacheType.sending(\.setTuistCacheType)
			) {
				ForEach(TuistCacheType.allCases, id: \.self) { cacheType in
					Text(cacheType.displayName).tag(cacheType)
				}
			}
			.pickerStyle(.segmented)

			Text(
				"Select the cache profile for warming. 'External Only' uses the 'only-external' profile (external dependencies only), while 'All Targets' uses 'all-possible' (internal targets too)."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var tuistExecutionSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Tuist Execution")
				.scaledFont(.headline)

			Picker(
				"Run via",
				selection: $store.tuistRunMode.sending(\.setTuistRunMode)
			) {
				ForEach(TuistRunMode.allCases, id: \.self) { mode in
					Text(mode.displayName).tag(mode)
				}
			}
			.pickerStyle(.segmented)

			if store.tuistRunMode == .mise {
				TextField(
					"mise Path",
					text: $store.misePath.sending(\.setMisePath)
				)
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)

				Text("Full path to the mise binary. Native install: ~/.local/bin/mise. Homebrew (Apple Silicon): /opt/homebrew/bin/mise.")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
			} else {
				Text("Tuist will be invoked directly from PATH without mise.")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
			}
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var worktreeOptionsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Worktree Options")
				.scaledFont(.headline)

			Toggle(
				"Delete Xcode DerivedData when removing worktree",
				isOn: $store.deleteDerivedDataOnWorktreeDelete
					.sending(\.setDeleteDerivedDataOnWorktreeDelete)
			)

			Text("Automatically deletes the associated Xcode DerivedData folder when a worktree is removed.")
				.scaledFont(.caption)
				.foregroundColor(.secondary)

			Text("Worktree Base Path")
				.scaledFont(.subheadline)
				.padding(.top, 4)

			TextField(
				"Worktree Base Path",
				text: $store.worktreeBasePath.sending(\.setWorktreeBasePath)
			)
			.textFieldStyle(.roundedBorder)
			.scaledFont(.body, design: .monospaced)

			Text(
				"Path where new worktrees are created. Can be relative to the repository (e.g. ../worktrees) or absolute."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var androidStudioPathSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Android Studio Path")
				.scaledFont(.headline)

			Text(
				"Specify the full path to the Android Studio executable. This is used to open Kotlin files within the project context."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)

			TextField("Android Studio Path", text: $store.androidStudioPath.sending(\.setAndroidStudioPath))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var repositoryGroupsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Repository Groups")
				.scaledFont(.headline)

			Text("Configure which platforms each repository group supports.")
				.scaledFont(.caption)
				.foregroundColor(.secondary)

			if store.trackedRepoPaths.isEmpty {
				Text("No repositories tracked yet.")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
			}
			else {
				ForEach(Array(store.trackedRepoPaths.enumerated()), id: \.element) { index, groupId in
					if index > 0 {
						Rectangle()
							.fill(Color.white)
							.frame(height: 1)
							.padding(.vertical, 6)
					}
					repoGroupRow(groupId: groupId)
				}
			}
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private func repoGroupRow(groupId: String) -> some View {
		let settings = store.groupSettings[groupId] ?? RepoGroupSettings()
		let isExpanded = expandedGroupIds.contains(groupId)

		return VStack(alignment: .leading, spacing: 8) {
			repoGroupHeader(groupId: groupId, settings: settings, isExpanded: isExpanded)

			if isExpanded {
				repoGroupDetails(groupId: groupId, settings: settings)
			}
		}
		.padding(10)
		.background(Color(NSColor.windowBackgroundColor))
		.cornerRadius(6)
	}

	private func repoGroupHeader(groupId: String, settings: RepoGroupSettings, isExpanded: Bool) -> some View {
		let platforms = [
			settings.supportsIOS ? "iOS" : nil,
			settings.supportsAndroid ? "Android" : nil,
			settings.supportsIOS && settings.supportsTuist ? "Tuist" : nil,
			settings.supportsWeb ? "Web" : nil,
		].compactMap(\.self)

		return Button {
			withAnimation(.easeInOut(duration: 0.2)) {
				if isExpanded {
					expandedGroupIds.remove(groupId)
				}
				else {
					expandedGroupIds.insert(groupId)
				}
			}
		} label: {
			HStack(spacing: 6) {
				Image(systemName: "chevron.right")
					.scaledFont(.caption, weight: .semibold)
					.foregroundColor(.secondary)
					.rotationEffect(.degrees(isExpanded ? 90 : 0))
					.frame(width: 12)

				Text(URL(fileURLWithPath: groupId).lastPathComponent)
					.scaledFont(.subheadline)
					.fontWeight(.semibold)

				if !platforms.isEmpty {
					Text(platforms.joined(separator: " · "))
						.scaledFont(.caption)
						.foregroundColor(.secondary)
				}

				Spacer()
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help(groupId)
	}

	private func repoGroupDetails(groupId: String, settings: RepoGroupSettings) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 20) {
				Toggle("iOS", isOn: Binding(
					get: { settings.supportsIOS },
					set: { store.send(.setGroupSupportsIOS(groupId: groupId, value: $0)) }
				))

				Toggle("Android", isOn: Binding(
					get: { settings.supportsAndroid },
					set: { store.send(.setGroupSupportsAndroid(groupId: groupId, value: $0)) }
				))

				if settings.supportsIOS {
					Toggle("Tuist", isOn: Binding(
						get: { settings.supportsTuist },
						set: { store.send(.setGroupSupportsTuist(groupId: groupId, value: $0)) }
					))
				}

				Toggle("Web", isOn: Binding(
					get: { settings.supportsWeb },
					set: { store.send(.setGroupSupportsWeb(groupId: groupId, value: $0)) }
				))
			}

			if settings.supportsIOS {
				HStack {
					Text("iOS Subfolder Path")
						.scaledFont(.caption)
						.foregroundColor(.secondary)
						.frame(width: 140, alignment: .leading)
					TextField("e.g. ios/MyApp", text: Binding(
						get: { settings.iosSubfolderPath },
						set: { store.send(.setGroupIOSSubfolderPath(groupId: groupId, path: $0)) }
					))
					.textFieldStyle(.roundedBorder)
					.scaledFont(.body, design: .monospaced)
				}

				HStack {
					Text("Xcode File Type")
						.scaledFont(.caption)
						.foregroundColor(.secondary)
						.frame(width: 140, alignment: .leading)
					Picker("Xcode File Type", selection: Binding(
						get: { settings.xcodeFilePreference },
						set: { store.send(.setGroupXcodeFilePreference(groupId: groupId, preference: $0)) }
					)) {
						ForEach(XcodeFilePreference.allCases, id: \.self) { pref in
							Text(pref.displayName).tag(pref)
						}
					}
					.pickerStyle(.segmented)
					.labelsHidden()
				}
			}

			if settings.supportsIOS, settings.supportsAndroid {
				HStack {
					Text("Mobile Subfolder Path")
						.scaledFont(.caption)
						.foregroundColor(.secondary)
						.frame(width: 140, alignment: .leading)
					TextField("e.g. mobile/App", text: Binding(
						get: { settings.mobileSubfolderPath },
						set: { store.send(.setGroupMobileSubfolderPath(groupId: groupId, path: $0)) }
					))
					.textFieldStyle(.roundedBorder)
					.scaledFont(.body, design: .monospaced)
				}
			}

			if settings.supportsWeb {
				HStack {
					Text("Web Index Path")
						.scaledFont(.caption)
						.foregroundColor(.secondary)
						.frame(width: 140, alignment: .leading)
					TextField("e.g. dist/index.html", text: Binding(
						get: { settings.webIndexPath },
						set: { store.send(.setGroupWebIndexPath(groupId: groupId, path: $0)) }
					))
					.textFieldStyle(.roundedBorder)
					.scaledFont(.body, design: .monospaced)
				}
			}

			HStack {
				Text("Default Branch")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
					.frame(width: 140, alignment: .leading)
				TextField("master / main (auto)", text: Binding(
					get: { settings.defaultBranch },
					set: { store.send(.setGroupDefaultBranch(groupId: groupId, value: $0)) }
				))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)
			}

			HStack {
				Text("Terminal Command")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
					.frame(width: 140, alignment: .leading)
				TextField("Overrides the global startup command (empty = use global)", text: Binding(
					get: { settings.terminalStartupCommand },
					set: { store.send(.setGroupTerminalStartupCommand(groupId: groupId, value: $0)) }
				))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)
			}

			HStack {
				Spacer()
					.frame(width: 140)
				Toggle("Don't run the global startup command", isOn: Binding(
					get: { settings.skipGlobalTerminalStartupCommand },
					set: { store.send(.setGroupSkipGlobalTerminalStartupCommand(groupId: groupId, value: $0)) }
				))
				.scaledFont(.caption)
				// A command of the group's own always wins, so the toggle only matters while it is blank.
				.disabled(!settings.terminalStartupCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}

			HStack {
				Text("Ticket ID Regex")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
					.frame(width: 140, alignment: .leading)
				TextField("e.g. MOB-[0-9]+", text: Binding(
					get: { settings.ticketIdRegex },
					set: { store.send(.setGroupTicketIdRegex(groupId: groupId, regex: $0)) }
				))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)
			}

			HStack {
				Text("YouTrack URL")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
					.frame(width: 140, alignment: .leading)
				TextField("https://org.youtrack.cloud (empty = disabled)", text: Binding(
					get: { settings.youtrackBaseURL },
					set: { store.send(.setGroupYouTrackBaseURL(groupId: groupId, value: $0)) }
				))
				.textFieldStyle(.roundedBorder)
				.scaledFont(.body, design: .monospaced)
			}

			HStack {
				Text("New Worktree Dialog Opens On")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
					.frame(width: 140, alignment: .leading)
				Picker("New Worktree Dialog Opens On", selection: Binding(
					get: { settings.openingWorktreeSource(fallback: store.defaultWorktreeSource) },
					set: { store.send(.setGroupDefaultWorktreeSource(groupId: groupId, source: $0)) }
				)) {
					ForEach(settings.worktreeSources, id: \.self) { source in
						Text(source.title).tag(source)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
			}

			Divider()
				.padding(.vertical, 4)

			VStack(alignment: .leading, spacing: 6) {
				Text("Files to copy into new worktrees")
					.scaledFont(.subheadline)
					.fontWeight(.semibold)
				Text("Relative paths to files or directories copied from this repository into each new worktree.")
					.scaledFont(.caption)
					.foregroundColor(.secondary)

				ForEach(Array(settings.worktreeCopyPaths.enumerated()), id: \.offset) { index, path in
					HStack {
						TextField("e.g. .env or config/local/", text: Binding(
							get: { path },
							set: { newValue in
								var updated = settings.worktreeCopyPaths
								guard index < updated.count else { return }
								updated[index] = newValue
								store.send(.setGroupWorktreeCopyPaths(groupId: groupId, value: updated))
							}
						))
						.textFieldStyle(.roundedBorder)
						.scaledFont(.body, design: .monospaced)

						Button {
							var updated = settings.worktreeCopyPaths
							guard index < updated.count else { return }
							updated.remove(at: index)
							store.send(.setGroupWorktreeCopyPaths(groupId: groupId, value: updated))
						} label: {
							Image(systemName: "minus.circle")
						}
						.buttonStyle(.borderless)
						.help("Remove path")
					}
				}

				Button {
					var updated = settings.worktreeCopyPaths
					updated.append("")
					store.send(.setGroupWorktreeCopyPaths(groupId: groupId, value: updated))
				} label: {
					Label("Add path", systemImage: "plus.circle")
						.scaledFont(.caption)
				}
				.buttonStyle(.borderless)
				.padding(.top, 2)
			}
		}
	}
}

#Preview {
	SettingsView(
		store: Store(initialState: SettingsReducer.State()) {
			SettingsReducer()
		},
		updates: { EmptyView() }
	)
}
