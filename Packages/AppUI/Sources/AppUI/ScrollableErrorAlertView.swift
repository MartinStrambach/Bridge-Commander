import ComposableArchitecture
import SwiftUI

// MARK: - GitAlertReducer

@Reducer
public struct ScrollableAlertReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public let title: String
		public let message: String
		public let isError: Bool
		/// Title of an extra button beside OK, offering a way out of what the alert reports.
		/// Tapping it sends `actionTapped`, which the presenting reducer handles (and dismisses
		/// the alert); with no title there is only OK.
		public let actionTitle: String?

		public init(title: String, message: String, isError: Bool, actionTitle: String? = nil) {
			self.title = title
			self.message = message
			self.isError = isError
			self.actionTitle = actionTitle
		}
	}

	public enum Action: Equatable {
		case dismissTapped
		case actionTapped
	}

	@Dependency(\.dismiss) var dismiss

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { _, action in
			switch action {
			case .dismissTapped:
				.run { _ in await dismiss() }
			case .actionTapped:
				.none
			}
		}
	}
}

// MARK: - ScrollableAlertView

public struct ScrollableAlertView: View {
	public let store: StoreOf<ScrollableAlertReducer>

	public init(store: StoreOf<ScrollableAlertReducer>) {
		self.store = store
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .center, spacing: 12) {
				Image(systemName: store.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
					.foregroundStyle(store.isError ? .red : .green)
					.scaledFont(size: 32)
				Text(store.title)
					.scaledFont(.headline)
			}

			ScrollView {
				Text(store.message)
					.scaledFont(.body, design: store.isError ? .monospaced : .default)
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(8)
					.lineLimit(nil)
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
				if let actionTitle = store.actionTitle {
					Button(actionTitle) {
						store.send(.actionTapped)
					}
					.buttonStyle(.scaledAutomatic)
				}
				Button("OK") {
					store.send(.dismissTapped)
				}
				.buttonStyle(.scaledAutomatic)
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(24)
		.frame(width: 440)
	}
}

#Preview("Error") {
	ScrollableAlertView(
		store: Store(
			initialState: ScrollableAlertReducer.State(
				title: "Pull Failed",
				message: """
				error: Your local changes to the following files would be overwritten by merge:
				\tsome/very/long/path/to/a/file.swift
				\tanother/path/to/file.swift
				Please commit your changes or stash them before you merge.
				Aborting
				""",
				isError: true
			)
		) {
			ScrollableAlertReducer()
		}
	)
}

#Preview("Error with action") {
	ScrollableAlertView(
		store: Store(
			initialState: ScrollableAlertReducer.State(
				title: "Push Failed",
				message: """
				Failed to push: To github.com:owner/repo.git
				 ! [rejected]        feature -> feature (non-fast-forward)
				error: failed to push some refs to 'github.com:owner/repo.git'
				""",
				isError: true,
				actionTitle: "Force Push"
			)
		) {
			ScrollableAlertReducer()
		}
	)
}

#Preview("Success") {
	ScrollableAlertView(
		store: Store(
			initialState: ScrollableAlertReducer.State(
				title: "Pull Successful",
				message: "Successfully pulled 3 commits from remote branch.",
				isError: false
			)
		) {
			ScrollableAlertReducer()
		}
	)
}
