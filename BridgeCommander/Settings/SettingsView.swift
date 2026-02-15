import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
	@Bindable
	var store: StoreOf<SettingsReducer>

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				Text("Settings")
					.font(.title2)
					.fontWeight(.bold)

				Divider()

				youtrackAuthenticationSection
				repositoryRefreshSection
				iosSubfolderSection
				ticketIdRegexSection
				branchNameRegexSection
				HStack(alignment: .top) {
					tuistCacheOptionsSection
					tuistGenerateOptionsSection
				}
				HStack(alignment: .top) {
					terminalBehaviorSection
					claudeCodeBehaviorSection
				}
				androidStudioPathSection
			}
			.padding()
		}
		.frame(minWidth: 500, idealWidth: 600, minHeight: 600, idealHeight: 800)
		.alert(store: store.scope(state: \.$alert, action: \.alert))
	}

	private var terminalBehaviorSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Terminal Opening Behavior")
				.font(.headline)

			Text("Choose how Terminal windows should open when clicking the Terminal button.")
				.font(.caption)
				.foregroundColor(.secondary)

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

	private var iosSubfolderSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("iOS Project Subfolder")
				.font(.headline)

			Text(
				"Specify the subfolder path within repositories where Tuist and Xcode actions should be executed (e.g., 'ios/FlashScore')."
			)
			.font(.caption)
			.foregroundColor(.secondary)

			TextField("iOS Subfolder Path", text: $store.iosSubfolderPath.sending(\.setIosSubfolderPath))
				.textFieldStyle(.roundedBorder)
				.font(.system(.body, design: .monospaced))
		}
		.padding()
		.background(Color(NSColor.controlBackgroundColor))
		.cornerRadius(8)
	}

	private var ticketIdRegexSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Ticket ID Regex Pattern")
				.font(.headline)

			Text(
				"Specify the regular expression pattern to extract ticket IDs from branch names (e.g., 'MOB-[0-9]+', 'JIRA-[0-9]+')."
			)
			.font(.caption)
			.foregroundColor(.secondary)

			TextField("Ticket ID Regex", text: $store.ticketIdRegex.sending(\.setTicketIdRegex))
				.textFieldStyle(.roundedBorder)
				.font(.system(.body, design: .monospaced))
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
}

#Preview {
	SettingsView(
		store: Store(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
	)
}
