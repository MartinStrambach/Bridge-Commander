import ComposableArchitecture
import SwiftUI

// MARK: - GitAlertReducer

@Reducer
public struct GitAlertReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public let title: String
		public let message: String
		public let isError: Bool

		public init(title: String, message: String, isError: Bool) {
			self.title = title
			self.message = message
			self.isError = isError
		}
	}

	public enum Action: Equatable {
		case dismissTapped
	}

	@Dependency(\.dismiss) var dismiss

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { _, action in
			switch action {
			case .dismissTapped:
				.run { _ in await dismiss() }
			}
		}
	}
}

// MARK: - ScrollableAlertView

public struct ScrollableAlertView: View {
	public let store: StoreOf<GitAlertReducer>

	public init(store: StoreOf<GitAlertReducer>) {
		self.store = store
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .center, spacing: 12) {
				Image(systemName: store.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
					.foregroundStyle(store.isError ? .red : .green)
					.font(.system(size: 32))
				Text(store.title)
					.font(.headline)
			}

			ScrollView {
				Text(store.message)
					.font(.system(.body, design: store.isError ? .monospaced : .default))
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
					store.send(.dismissTapped)
				}
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
			initialState: GitAlertReducer.State(
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
			GitAlertReducer()
		}
	)
}

#Preview("Success") {
	ScrollableAlertView(
		store: Store(
			initialState: GitAlertReducer.State(
				title: "Pull Successful",
				message: "Successfully pulled 3 commits from remote branch.",
				isError: false
			)
		) {
			GitAlertReducer()
		}
	)
}
