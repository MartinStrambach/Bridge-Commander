import ComposableArchitecture
import SwiftUI

// MARK: - Claude Code Button View

struct ClaudeCodeButtonView: View {
	let store: StoreOf<ClaudeCodeButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		Group {
			if store.isLaunching {
				HStack(spacing: 8) {
					ProgressView()
					Text(buttonLabel)
						.font(.body)
				}
				.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 120)
				.buttonStyle(.borderedProminent)
				.tint(.purple)
			}
			else {
				Button(action: { store.send(.launchClaudeCodeButtonTapped) }) {
					Label(buttonLabel, systemImage: buttonIcon)
						.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 120)
				}
				.buttonStyle(.bordered)
			}
		}
		.controlSize(.small)
		.fixedSize(horizontal: true, vertical: false)
		.disabled(store.isLaunching)
		.help(buttonTooltip)
		.alert("Failed to Launch Claude Code", isPresented: .constant(store.errorMessage != nil)) {
			Button("OK") {
				store.send(.dismissError)
			}
		} message: {
			if let errorMessage = store.errorMessage {
				Text(errorMessage)
			}
		}
	}

	// MARK: - Computed Properties

	private var buttonLabel: String {
		if store.isLaunching {
			abbreviationMode.isAbbreviated ? "Launch" : "Launching"
		}
		else {
			abbreviationMode.isAbbreviated ? "CC" : "Claude Code"
		}
	}

	private var buttonIcon: String {
		"sparkles"
	}

	private var buttonTooltip: String {
		if let errorMessage = store.errorMessage {
			"Error: \(errorMessage)"
		}
		else if store.isLaunching {
			"Launching Claude Code..."
		}
		else {
			"Launch Claude Code in repository"
		}
	}
}

#Preview {
	ClaudeCodeButtonView(
		store: Store(
			initialState: ClaudeCodeButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				ClaudeCodeButtonReducer()
			}
		)
	)
	.environmentObject(AbbreviationMode())
}
