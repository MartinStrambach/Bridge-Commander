import ComposableArchitecture
import SwiftUI

// MARK: - Xcode Project Button View

struct XcodeProjectButtonView: View {
	let store: StoreOf<XcodeProjectButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		Group {
			if store.projectState.isProcessing {
				HStack(spacing: 8) {
					ProgressView()
						.scaleEffect(0.5)
					Text(buttonLabel)
						.font(.body)
				}
				.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 120)
				.buttonStyle(.borderedProminent)
			}
			else {
				Button(action: { store.send(.openProject) }) {
					Label(buttonLabel, systemImage: buttonIcon)
						.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 120)
				}
				.buttonStyle(.bordered)
			}
		}
		.tint(store.projectPath == nil ? .orange : nil)
		.controlSize(.small)
		.fixedSize(horizontal: true, vertical: false)
		.disabled(store.projectState.isProcessing)
		.help(buttonTooltip)
		.alert("No Xcode Project Found", isPresented: .constant(store.showingWarning)) {
			Button("Cancel", role: .cancel) {
				store.send(.dismissWarning)
			}
			Button("Generate") {
				store.send(.generateProject)
			}
		} message: {
			Text("No Xcode project or workspace was found.\n\nWould you like to generate one?")
		}
		.task {
			store.send(.onAppear)
		}
	}

	// MARK: - Computed Properties

	private var buttonLabel: String {
		switch store.projectState {
		case .idle:
			if store.projectPath == nil {
				abbreviationMode.isAbbreviated ? "Gen" : "Generate"
			}
			else {
				abbreviationMode.isAbbreviated ? "Xcd" : "Xcode"
			}

		case .checking:
			abbreviationMode.isAbbreviated ? "Chck" : "Checking"

		case .runningTi:
			abbreviationMode.isAbbreviated ? "ti" : "Running ti"

		case .runningTg:
			abbreviationMode.isAbbreviated ? "tg" : "Running tg"

		case .opening:
			abbreviationMode.isAbbreviated ? "Opn" : "Opening"

		case .error:
			abbreviationMode.isAbbreviated ? "Xcd" : "Xcode"
		}
	}

	private var buttonIcon: String {
		if store.projectPath == nil, store.projectState == .idle {
			"exclamationmark.triangle"
		}
		else {
			"hammer"
		}
	}

	private var buttonTooltip: String {
		switch store.projectState {
		case .idle:
			if store.projectPath == nil {
				"Xcode project not found - click to generate"
			}
			else {
				"Open Xcode project or workspace"
			}

		case .error:
			"Error: \(store.errorMessage ?? "unknown")"

		default:
			store.projectState.displayMessage
		}
	}
}

#Preview {
	XcodeProjectButtonView(
		store: Store(
			initialState: XcodeProjectButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				XcodeProjectButtonReducer()
			}
		)
	)
	.environmentObject(AbbreviationMode())
}
