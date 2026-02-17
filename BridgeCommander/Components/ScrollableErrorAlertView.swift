import SwiftUI

private struct ScrollableAlertView: View {
	private let title: String
	private let message: String
	private let isError: Bool
	private let onDismiss: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .center, spacing: 12) {
				Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
					.foregroundStyle(isError ? .red : .green)
					.font(.system(size: 32))
				Text(title)
					.font(.headline)
			}

			ScrollView {
				Text(message)
					.font(.system(.body, design: isError ? .monospaced : .default))
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(8)
			}
			.frame(height: 200)
			.background(Color(NSColor.textBackgroundColor))
			.clipShape(RoundedRectangle(cornerRadius: 6))
			.overlay(
				RoundedRectangle(cornerRadius: 6)
					.stroke(Color(NSColor.separatorColor), lineWidth: 1)
			)

			HStack {
				Spacer()
				Button("OK") {
					onDismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(24)
		.frame(width: 440)
	}

	init(title: String, message: String, isError: Bool, onDismiss: @escaping () -> Void) {
		self.title = title
		self.message = message
		self.isError = isError
		self.onDismiss = onDismiss
	}
}

// MARK: - View Modifier

private struct ScrollableAlertModifier: ViewModifier {
	@State
	private var isPresented = false
	@State
	private var displayedAlert: GitAlert?

	private let alert: GitAlert?

	init(alert: GitAlert?) {
		self.alert = alert
	}

	func body(content: Content) -> some View {
		content
			.sheet(isPresented: $isPresented) {
				if let displayedAlert {
					ScrollableAlertView(
						title: displayedAlert.title,
						message: displayedAlert.message,
						isError: displayedAlert.isError,
						onDismiss: { isPresented = false }
					)
				}
			}
			.onChange(of: alert) { _, newAlert in
				if let newAlert {
					displayedAlert = newAlert
					isPresented = true
				}
			}
	}
}

extension View {
	func scrollableAlert(_ alert: GitAlert?) -> some View {
		modifier(ScrollableAlertModifier(alert: alert))
	}
}

#Preview("Error") {
	ScrollableAlertView(
		title: "Pull Failed",
		message: """
		error: Your local changes to the following files would be overwritten by merge:
		\tsome/very/long/path/to/a/file.swift
		\tanother/path/to/file.swift
		Please commit your changes or stash them before you merge.
		Aborting
		""",
		isError: true,
		onDismiss: {}
	)
}

#Preview("Success") {
	ScrollableAlertView(
		title: "Pull Successful",
		message: "Successfully pulled 3 commits from remote branch.",
		isError: false,
		onDismiss: {}
	)
}
