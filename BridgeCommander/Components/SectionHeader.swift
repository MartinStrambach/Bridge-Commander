import SwiftUI

struct SectionHeader: View {
	let title: String
	let count: Int
	var actionTitle: String?
	var action: (() -> Void)?

	var body: some View {
		HStack {
			Text(title)
				.font(.headline)
				.foregroundStyle(.secondary)
			Spacer()

			if let actionTitle, let action, count > 0 {
				Button(actionTitle) {
					action()
				}
				.font(.caption)
				.buttonStyle(.borderless)
			}

			Text("\(count)")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(Color(nsColor: .controlBackgroundColor))
	}
}
