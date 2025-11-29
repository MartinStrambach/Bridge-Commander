import SwiftUI

struct SettingsView: View {
	@ObservedObject
	var settings: AppSettings

	@State
	private var showTokenClearedAlert = false

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

				SecureField("YouTrack Auth Token", text: $settings.youtrackAuthToken)
					.textFieldStyle(.roundedBorder)
					.font(.system(.body, design: .monospaced))

				Button(action: { showTokenClearedAlert = true }) {
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

				Picker("Refresh Interval", selection: $settings.periodicRefreshInterval) {
					ForEach(PeriodicRefreshInterval.allCases, id: \.self) { interval in
						Text(interval.displayName).tag(interval)
					}
				}
				.pickerStyle(.segmented)
			}
			.padding()
			.background(Color(NSColor.controlBackgroundColor))
			.cornerRadius(8)

			Spacer()
		}
		.padding()
		.frame(minWidth: 500, minHeight: 300)
		.alert("Clear Token", isPresented: $showTokenClearedAlert) {
			Button("Cancel", role: .cancel) {}
			Button("Clear", role: .destructive) {
				settings.clear()
			}
		} message: {
			Text("Are you sure you want to clear the token? YouTrack features will not work without a valid token.")
		}
	}
}

#Preview {
	SettingsView(settings: AppSettings())
}
