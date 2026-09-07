import GitHosting
import SwiftUI

/// Overlapping circular avatars for the people who acted on a PR/MR.
///
/// Each circle loads the provider's avatar and falls back to a colored monogram —
/// which is also what shows while the image is in flight, so the stack never
/// reflows once an avatar arrives. `AsyncImage` goes through `URLSession.shared`,
/// whose `URLCache` absorbs the repeated loads caused by the row's periodic
/// refresh; both providers serve avatars with long-lived cache headers.
struct ApproverAvatarStack: View {
	let reviewers: [Reviewer]
	/// Beyond this, the remainder collapses into a "+N" circle. Three keeps the
	/// stack inside roughly one action-button width.
	var maxShown = 3
	var diameter: CGFloat = 20

	/// Negative leading inset applied to every circle but the first.
	private var overlap: CGFloat { diameter * 0.375 }

	var body: some View {
		HStack(spacing: 0) {
			ForEach(Array(shown.enumerated()), id: \.element.id) { index, reviewer in
				avatar(for: reviewer)
					.padding(.leading, index == 0 ? 0 : -overlap)
					.zIndex(Double(maxShown - index))
			}

			if overflowCount > 0 {
				overflowCircle
					.padding(.leading, shown.isEmpty ? 0 : -overlap)
			}
		}
		.help(reviewers.map(\.displayName).joined(separator: ", "))
	}

	private var shown: [Reviewer] {
		Array(reviewers.prefix(maxShown))
	}

	private var overflowCount: Int {
		max(0, reviewers.count - maxShown)
	}

	/// Pixels to request from the host. 3x the drawn size covers the densest
	/// display without asking for the multi-hundred-KB originals.
	private var requestedPixels: Int {
		Int(diameter * 3)
	}

	@ViewBuilder
	private func avatar(for reviewer: Reviewer) -> some View {
		Group {
			if let url = reviewer.avatarURL(pixels: requestedPixels) {
				AsyncImage(url: url) { image in
					image
						.resizable()
						.interpolation(.high)
						.antialiased(true)
						.scaledToFill()
				} placeholder: {
					// Also the failure state: AsyncImage's default builder shows the
					// placeholder for `.empty` and `.failure` alike, so a broken avatar
					// URL degrades to the monogram instead of a blank hole.
					monogram(for: reviewer)
				}
			}
			else {
				monogram(for: reviewer)
			}
		}
		.frame(width: diameter, height: diameter)
		.clipShape(Circle())
		.overlay(Circle().strokeBorder(Color(NSColor.controlBackgroundColor), lineWidth: 1))
	}

	private func monogram(for reviewer: Reviewer) -> some View {
		Circle()
			.fill(Self.palette[reviewer.colorIndex % Self.palette.count])
			.overlay(
				Text(reviewer.initials)
					.font(.system(size: diameter * 0.45, weight: .semibold))
					.foregroundStyle(.white)
					.minimumScaleFactor(0.5)
					.lineLimit(1)
			)
	}

	private var overflowCircle: some View {
		Circle()
			.fill(Color.secondary.opacity(0.3))
			.frame(width: diameter, height: diameter)
			.overlay(
				Text("+\(overflowCount)")
					.font(.system(size: diameter * 0.4, weight: .semibold))
					.foregroundStyle(.primary)
					.minimumScaleFactor(0.5)
					.lineLimit(1)
			)
			.overlay(Circle().strokeBorder(Color(NSColor.controlBackgroundColor), lineWidth: 1))
	}

	/// Indexed by `Reviewer.colorIndex`, which is a stable fold over the username —
	/// so a given person keeps the same color across launches.
	/// Must hold `Reviewer.colorCount` entries.
	private static let palette: [Color] = [
		.blue, .purple, .pink, .teal, .indigo, .cyan, .mint, .brown,
	]
}

#Preview {
	VStack(alignment: .leading, spacing: 12) {
		ApproverAvatarStack(reviewers: [
			Reviewer(username: "astrid", displayName: "Astrid Berg"),
		])
		ApproverAvatarStack(reviewers: [
			Reviewer(username: "astrid", displayName: "Astrid Berg"),
			Reviewer(username: "cdupont", displayName: "Camille Dupont"),
		])
		ApproverAvatarStack(reviewers: [
			Reviewer(username: "astrid", displayName: "Astrid Berg"),
			Reviewer(username: "cdupont", displayName: "Camille Dupont"),
			Reviewer(username: "rmehta", displayName: "Rohan Mehta"),
			Reviewer(username: "jlee", displayName: "Jordan Lee"),
			Reviewer(username: "tokafor", displayName: "Tomi Okafor"),
		])
	}
	.padding()
}
