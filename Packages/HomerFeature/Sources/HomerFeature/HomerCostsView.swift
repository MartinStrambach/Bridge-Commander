import ComposableArchitecture
import SwiftUI

/// The Costs page of the selected instance.
struct HomerCostsView: View {
	let store: StoreOf<HomerCostsReducer>

	var body: some View {
		ContentUnavailableView("Costs", systemImage: "dollarsign.circle")
	}
}
