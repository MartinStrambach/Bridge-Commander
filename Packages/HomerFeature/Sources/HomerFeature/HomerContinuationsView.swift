import ComposableArchitecture
import SwiftUI

/// The Continuations page of the selected instance.
struct HomerContinuationsView: View {
	let store: StoreOf<HomerContinuationsReducer>

	var body: some View {
		ContentUnavailableView("Continuations", systemImage: "point.3.connected.trianglepath.dotted")
	}
}
