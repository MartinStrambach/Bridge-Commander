import ComposableArchitecture
import GitHosting
import SwiftUI
import ToolsIntegration

public struct SettingsView: View {
	@Bindable
	public var store: StoreOf<SettingsReducer>

	public init(store: StoreOf<SettingsReducer>) {
		self.store = store
	}

	public var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				Text("Settings")
					.font(.title2)
					.fontWeight(.bold)

				Divider()

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
				androidStudioPathSection
				worktreeOptionsSection
				repositoryGroupsSection
			}
			.padding()
		}
		.frame(minWidth: 500, idealWidth: 600, minHeight: 600, idealHeight: 800)
		.alert($store.scope(state: \.$alert, action: \.alert))
	}

	private var terminalBehaviorSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Terminal")
				.font(.headline)

			Text("Choose which terminal app opens when clicking the Terminal button.")
				.font(.caption)
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
				.font(.headline)

			Text("Choose how Claude Code should open when clicking the Claude Code button.")
				.font(.caption)
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
				.font(.headline)

			Text("Choose the color theme for the built-in terminal. Applies to newly opened terminals.")
				.font(.caption)
				.foregroundColor(.secondary)

			Picker(
				"Color Theme",
				selection: $store.terminalColorTheme.sending(\.setTerminalColorTheme)
			) {
				ForEach(TerminalColorTheme.allCases, id: \.self) { theme in
					Text(theme.displayName).tag(theme)
				}
			}
			.pickerStyle(.segmented)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var youtrackAuthenticationSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("YouTrack Authentication")
				.font(.headline)

			Text(
				"Enter your YouTrack personal access token. This token will be stored locally and used to fetch issue details."
			)
			.font(.caption)
			.foregroundColor(.secondary)

			SecureField("YouTrack Auth Token", text: $store.youtrackAuthToken.sending(\.setYouTrackToken))
				.textFieldStyle(.roundedBorder)
				.font(.system(.body, design: .monospaced))

			Button(action: { store.send(.clearTokenButtonTapped) }) {
				Label("Clear Token", systemImage: "xmark.circle")
			}
			.buttonStyle(.bordered)
			.foregroundColor(.red)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var gitHubAuthenticationSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("GitHub Authentication")
				.font(.headline)

			Text(
				"Enter a GitHub personal access token (classic or fine-grained) with `pull_requests: read` scope. Used to detect open PRs for the current branch."
			)
			.font(.caption)
			.foregroundColor(.secondary)

			SecureField("GitHub Token", text: $store.githubToken.sending(\.setGitHubToken))
				.textFieldStyle(.roundedBorder)
				.font(.system(.body, design: .monospaced))

			Button(action: { store.send(.clearGitHubToken) }) {
				Label("Clear Token", systemImage: "xmark.circle")
			}
			.buttonStyle(.bordered)
			.foregroundColor(.red)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var gitLabAuthenticationSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("GitLab Authentication")
				.font(.headline)

			Text(
				"Enter a GitLab personal access token with `read_api` scope. Used to detect open merge requests for the current branch."
			)
			.font(.caption)
			.foregroundColor(.secondary)

			SecureField("GitLab Token", text: $store.gitlabToken.sending(\.setGitLabToken))
				.textFieldStyle(.roundedBorder)
				.font(.system(.body, design: .monospaced))

			Button(action: { store.send(.clearGitLabToken) }) {
				Label("Clear Token", systemImage: "xmark.circle")
			}
			.buttonStyle(.bordered)
			.foregroundColor(.red)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var repositoryRefreshSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Repository Refresh")
				.font(.headline)

			Text("Automatically refresh repository status at the selected interval.")
				.font(.caption)
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
				.font(.headline)

			Text(
				"Specify the regular expression pattern to remove project prefixes from branch names (e.g., '[a-zA-Z]+-\\\\d+[_/]' matches 'MOB-123_' or 'tech-60/')."
			)
			.font(.caption)
			.foregroundColor(.secondary)

			TextField("Branch Name Regex", text: $store.branchNameRegex.sending(\.setBranchNameRegex))
				.textFieldStyle(.roundedBorder)
				.font(.system(.body, design: .monospaced))
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var tuistGenerateOptionsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Tuist Generate Options")
				.font(.headline)

			Toggle(
				"Open Xcode after generating project",
				isOn: $store.openXcodeAfterGenerate.sending(\.setOpenXcodeAfterGenerate)
			)

			Text(
				"Automatically open the generated Xcode project after running 'tuist generate'."
			)
			.font(.caption)
			.foregroundColor(.secondary)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var tuistCacheOptionsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Tuist Cache Options")
				.font(.headline)

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
				"Select which targets to cache. 'External Only' caches only external dependencies, while 'All Targets' caches all project targets."
			)
			.font(.caption)
			.foregroundColor(.secondary)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var tuistExecutionSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Tuist Execution")
				.font(.headline)

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
				.font(.system(.body, design: .monospaced))

				Text("Full path to the mise binary. Native install: ~/.local/bin/mise. Homebrew (Apple Silicon): /opt/homebrew/bin/mise.")
					.font(.caption)
					.foregroundColor(.secondary)
			} else {
				Text("Tuist will be invoked directly from PATH without mise.")
					.font(.caption)
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
				.font(.headline)

			Toggle(
				"Delete Xcode DerivedData when removing worktree",
				isOn: $store.deleteDerivedDataOnWorktreeDelete
					.sending(\.setDeleteDerivedDataOnWorktreeDelete)
			)

			Text("Automatically deletes the associated Xcode DerivedData folder when a worktree is removed.")
				.font(.caption)
				.foregroundColor(.secondary)

			Text("Worktree Base Path")
				.font(.subheadline)
				.padding(.top, 4)

			TextField(
				"Worktree Base Path",
				text: $store.worktreeBasePath.sending(\.setWorktreeBasePath)
			)
			.textFieldStyle(.roundedBorder)
			.font(.system(.body, design: .monospaced))

			Text(
				"Path where new worktrees are created. Can be relative to the repository (e.g. ../worktrees) or absolute."
			)
			.font(.caption)
			.foregroundColor(.secondary)
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var androidStudioPathSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Android Studio Path")
				.font(.headline)

			Text(
				"Specify the full path to the Android Studio executable. This is used to open Kotlin files within the project context."
			)
			.font(.caption)
			.foregroundColor(.secondary)

			TextField("Android Studio Path", text: $store.androidStudioPath.sending(\.setAndroidStudioPath))
				.textFieldStyle(.roundedBorder)
				.font(.system(.body, design: .monospaced))
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var repositoryGroupsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Repository Groups")
				.font(.headline)

			Text("Configure which platforms each repository group supports.")
				.font(.caption)
				.foregroundColor(.secondary)

			if store.trackedRepoPaths.isEmpty {
				Text("No repositories tracked yet.")
					.font(.caption)
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
		let groupName = URL(fileURLWithPath: groupId).lastPathComponent

		return VStack(alignment: .leading, spacing: 8) {
			Text(groupName)
				.font(.subheadline)
				.fontWeight(.semibold)

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
			}

			if settings.supportsIOS {
				HStack {
					Text("iOS Subfolder Path")
						.font(.caption)
						.foregroundColor(.secondary)
						.frame(width: 140, alignment: .leading)
					TextField("e.g. ios/MyApp", text: Binding(
						get: { settings.iosSubfolderPath },
						set: { store.send(.setGroupIOSSubfolderPath(groupId: groupId, path: $0)) }
					))
					.textFieldStyle(.roundedBorder)
					.font(.system(.body, design: .monospaced))
				}

				HStack {
					Text("Xcode File Type")
						.font(.caption)
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
						.font(.caption)
						.foregroundColor(.secondary)
						.frame(width: 140, alignment: .leading)
					TextField("e.g. mobile/App", text: Binding(
						get: { settings.mobileSubfolderPath },
						set: { store.send(.setGroupMobileSubfolderPath(groupId: groupId, path: $0)) }
					))
					.textFieldStyle(.roundedBorder)
					.font(.system(.body, design: .monospaced))
				}
			}

			HStack {
				Text("Ticket ID Regex")
					.font(.caption)
					.foregroundColor(.secondary)
					.frame(width: 140, alignment: .leading)
				TextField("e.g. MOB-[0-9]+", text: Binding(
					get: { settings.ticketIdRegex },
					set: { store.send(.setGroupTicketIdRegex(groupId: groupId, regex: $0)) }
				))
				.textFieldStyle(.roundedBorder)
				.font(.system(.body, design: .monospaced))
			}

			Divider()
				.padding(.vertical, 4)

			VStack(alignment: .leading, spacing: 6) {
				Text("Files to copy into new worktrees")
					.font(.subheadline)
					.fontWeight(.semibold)
				Text("Relative paths to files or directories copied from this repository into each new worktree.")
					.font(.caption)
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
						.font(.system(.body, design: .monospaced))

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
						.font(.caption)
				}
				.buttonStyle(.borderless)
				.padding(.top, 2)
			}
		}
		.padding(10)
		.background(Color(NSColor.windowBackgroundColor))
		.cornerRadius(6)
	}
}

#Preview {
	SettingsView(
		store: Store(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
	)
}
