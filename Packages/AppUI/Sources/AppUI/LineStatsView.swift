import SwiftUI

/// Compact "+N −M" added/removed line counts, as shown next to files and section totals.
public struct LineStatsView: View {
	public let addedLines: Int
	public let removedLines: Int

	public init(addedLines: Int, removedLines: Int) {
		self.addedLines = addedLines
		self.removedLines = removedLines
	}

	public var body: some View {
		HStack(spacing: 4) {
			Text("+\(addedLines)")
				.foregroundStyle(.green)
			Text("−\(removedLines)")
				.foregroundStyle(.red)
		}
		.font(.caption.monospacedDigit())
	}
}
