import ComposableArchitecture
import SwiftUI

// MARK: - Xcode Project Button View

struct XcodeProjectButtonView: View {
	let store: StoreOf<XcodeProjectButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		ToolButton(
			label: buttonLabel,
			icon: .systemImage(buttonIcon),
			tooltip: buttonTooltip,
			isProcessing: store.projectState.isProcessing,
			tint: store.projectPath == nil ? .orange : nil,
			action: { store.send(.openProject) }
		)
		.environmentObject(abbreviationMode)
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
