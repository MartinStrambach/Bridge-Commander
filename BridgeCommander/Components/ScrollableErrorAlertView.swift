import ComposableArchitecture
import SwiftUI

// MARK: - GitAlertReducer

@Reducer
struct GitAlertReducer {
	@ObservableState
	struct State: Equatable {
		let title: String
		let message: String
		let isError: Bool
	}

	enum Action: Equatable {
		case dismissTapped
	}

	@Dependency(\.dismiss) var dismiss

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .dismissTapped:
				return .run { _ in await dismiss() }
			}
		}
	}
}

// MARK: - ScrollableAlertView

struct ScrollableAlertView: View {
	let store: StoreOf<GitAlertReducer>

	var body: some View {
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
