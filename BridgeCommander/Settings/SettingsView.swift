import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
	@Bindable
	var store: StoreOf<SettingsReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Settings")
				.font(.title2)
				.fontWeight(.bold)

			Divider()

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
		.padding()
		.frame(minWidth: 500, minHeight: 300)
		.fixedSize(horizontal: true, vertical: true)
		.alert(store: store.scope(state: \.$alert, action: \.alert))
	}
}

#Preview {
	SettingsView(
		store: Store(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
	)
}
