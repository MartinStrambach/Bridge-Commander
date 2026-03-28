import SwiftUI

public struct EmptyStateView: View {
	public let title: String
	public let systemImage: String
	public let description: String

	public init(title: String, systemImage: String, description: String) {
		self.title = title
		self.systemImage = systemImage
		self.description = description
	}

	public var body: some View {
		VStack {
			Spacer()
			ContentUnavailableView(
				title,
				systemImage: systemImage,
				description: Text(description)
			)
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
