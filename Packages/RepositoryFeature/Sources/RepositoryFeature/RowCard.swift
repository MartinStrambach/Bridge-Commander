import AppKit
import AppUI
import SwiftUI

/// The rounded card a repository list row sits on. The list hides its own background, so the cards
/// stand on the window's: white over the light window, a faint lift over the dark one. A group's
/// header card is a step stronger than its worktrees' so the repository reads as their parent.
struct RowCardBackground: View {
	var isGroupHeader: Bool
	var isHovered: Bool

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
		shape
			.fill(Self.fill(isGroupHeader: isGroupHeader))
			.overlay {
				shape.strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.07))
			}
			.shadow(color: .black.opacity(isGroupHeader ? 0.07 : 0.04), radius: 1.5, y: 1)
			.animation(.easeOut(duration: 0.12), value: isHovered)
	}

	/// The card's colour — opaque, so a badge can be ringed in it and a pinned group header hides
	/// the rows scrolling under it.
	static func fill(isGroupHeader: Bool) -> Color {
		isGroupHeader ? headerFill : worktreeFill
	}

	private static let headerFill = windowBackground(liftedBy: (light: 1, dark: 0.09))
	private static let worktreeFill = windowBackground(liftedBy: (light: 0.7, dark: 0.05))

	/// The window background mixed toward white by the given fraction, per appearance.
	private static func windowBackground(liftedBy fraction: (light: CGFloat, dark: CGFloat)) -> Color {
		Color(nsColor: NSColor(name: nil) { appearance in
			let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			var color = NSColor.white
			appearance.performAsCurrentDrawingAppearance {
				color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)?
					.blended(withFraction: isDark ? fraction.dark : fraction.light, of: .white) ?? .white
			}
			return color
		})
	}
}

/// A small tinted capsule — an SF Symbol and a short text — for the counts and flags on a row
/// (changes, worktrees, merge, no remote).
struct RowChip: View {
	let systemImage: String
	let text: String
	let color: Color
	var help: String?

	var body: some View {
		// No tooltip modifier at all without help text: most chips have none.
		if let help {
			chip.help(help)
		}
		else {
			chip
		}
	}

	private var chip: some View {
		HStack(spacing: 3) {
			Image(systemName: systemImage)
				.scaledFont(.caption2)
				.fontWeight(.semibold)
			Text(text)
				.scaledFont(.caption)
				.fontWeight(.medium)
				.monospacedDigit()
				.lineLimit(1)
		}
		.foregroundStyle(color)
		.padding(.horizontal, 6)
		.padding(.vertical, 2)
		.background(color.opacity(0.14), in: Capsule())
		.fixedSize()
	}
}

#Preview {
	VStack(spacing: 6) {
		HStack {
			RowChip(systemImage: "tree.fill", text: "3", color: .blue)
			RowChip(systemImage: "checkmark", text: "2", color: .green)
			RowChip(systemImage: "pencil", text: "5", color: .orange)
			RowChip(systemImage: "icloud.slash.fill", text: "No remote", color: .orange)
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(RowCardBackground(isGroupHeader: true, isHovered: false))
		Text("Worktree")
			.padding(12)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(RowCardBackground(isGroupHeader: false, isHovered: true))
	}
	.padding()
	.frame(width: 420)
}
