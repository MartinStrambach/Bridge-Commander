import SwiftUI

/// A repository's or worktree's symbol on a tinted rounded tile, with a badge while a merge is in
/// progress. The tile grows with the app's text scale, so the glyph never outgrows it.
public struct RepositoryIcon: View {
	public let isWorktree: Bool
	public let isMergeInProgress: Bool

	@Environment(\.uiFontScale)
	private var uiFontScale

	public init(isWorktree: Bool, isMergeInProgress: Bool) {
		self.isWorktree = isWorktree
		self.isMergeInProgress = isMergeInProgress
	}

	private var tint: Color {
		isWorktree ? .blue : .green
	}

	public var body: some View {
		ZStack(alignment: .topTrailing) {
			Image(systemName: isWorktree ? "tree.fill" : "folder.badge.gearshape")
				.scaledFont(.title3)
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(tint)
				.frame(width: 32 * uiFontScale, height: 32 * uiFontScale)
				.background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8 * uiFontScale, style: .continuous))

			// Merge indicator badge
			if isMergeInProgress {
				Image(systemName: "arrow.triangle.swap")
					.font(.system(size: 10, weight: .bold))
					.foregroundColor(.white)
					.frame(width: 16, height: 16)
					.background(Circle().fill(Color.red))
					.offset(x: 5, y: -5)
			}
		}
	}
}

#Preview {
	HStack(spacing: 20) {
		RepositoryIcon(isWorktree: false, isMergeInProgress: false)
		RepositoryIcon(isWorktree: true, isMergeInProgress: false)
		RepositoryIcon(isWorktree: false, isMergeInProgress: true)
		RepositoryIcon(isWorktree: true, isMergeInProgress: true)
	}
	.padding()
}
