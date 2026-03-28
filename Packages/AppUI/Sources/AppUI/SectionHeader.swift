import SwiftUI

public struct SectionHeader: View {
	public let title: String
	public let count: Int
	public var actionTitle: String?
	public var action: (() -> Void)?

	public init(title: String, count: Int, actionTitle: String? = nil, action: (() -> Void)? = nil) {
		self.title = title
		self.count = count
		self.actionTitle = actionTitle
		self.action = action
	}

	public var body: some View {
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
