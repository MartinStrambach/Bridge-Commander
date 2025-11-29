import ComposableArchitecture
import SwiftUI

// MARK: - Android Studio Button View

struct AndroidStudioButtonView: View {
	let store: StoreOf<AndroidStudioButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		Group {
			if store.isOpening {
				HStack(spacing: 8) {
					ProgressView()
						.scaleEffect(0.5)
					Text(buttonLabel)
						.font(.body)
				}
				.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 120)
				.buttonStyle(.borderedProminent)
				.tint(.green)
			}
			else {
				Button(action: { store.send(.openAndroidStudioButtonTapped) }) {
					Label {
						Text(buttonLabel)
					} icon: {
						Image("android")
							.resizable()
							.renderingMode(.template)
							.scaledToFit()
							.frame(height: 11)
							.foregroundStyle(.white)
					}
					.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 120)
				}
				.buttonStyle(.bordered)
			}
		}
		.controlSize(.small)
		.fixedSize(horizontal: true, vertical: false)
		.disabled(store.isOpening)
		.help(buttonTooltip)
		.alert("Failed to Open Android Studio", isPresented: .constant(store.errorMessage != nil)) {
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
		if store.isOpening {
			abbreviationMode.isAbbreviated ? "Open" : "Opening"
		}
		else {
			abbreviationMode.isAbbreviated ? "AS" : "Android Studio"
		}
	}

	private var buttonIcon: String {
		"square.stack.3d.up.badge.automatic.fill"
	}

	private var buttonTooltip: String {
		if let errorMessage = store.errorMessage {
			"Error: \(errorMessage)"
		}
		else if store.isOpening {
			"Opening Android Studio..."
		}
		else {
			"Open in Android Studio"
		}
	}
}

#Preview {
	AndroidStudioButtonView(
		store: Store(
			initialState: AndroidStudioButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				AndroidStudioButtonReducer()
			}
		)
	)
	.environmentObject(AbbreviationMode())
}
