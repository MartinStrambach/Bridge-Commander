import SwiftUI

/// Draws each hunk as a rounded, bordered card even though its header, lines and footer are
/// separate items of `DiffViewer`'s single `LazyVStack`.
///
/// The card must not be a container view: wrapping a hunk's lines in their own stack, lazy or
/// not, means the outer lazy stack has to size the whole hunk to place it. A nested `LazyVStack`
/// then re-measures every line on each lazy phase change and a whole-file hunk (an untracked
/// file is one hunk) can pin the main thread for minutes. Keeping every line a direct lazy item
/// bounds the work to the visible rows, so the card is assembled from a top cap (header), a side
/// border on each row and a bottom cap (footer).
enum HunkCard {
	static let cornerRadius: CGFloat = 6
	static let borderWidth: CGFloat = 1
	/// Space between the card and the diff pane's edge.
	static let horizontalInset: CGFloat = 12
	/// Space between the card and the previous / next item.
	static let verticalGap: CGFloat = 8

	static var fill: Color { Color(nsColor: .textBackgroundColor) }
	static var border: Color { Color(nsColor: .separatorColor) }
	static var headerFill: Color { Color(nsColor: .controlBackgroundColor) }
}

// MARK: - Header

/// Hunk header bar with the stage / unstage / discard actions. Closes the card at the top.
/// A nil `actions` leaves the bar with just the hunk range, for a read-only diff.
struct HunkHeaderView: View {
	let hunk: DiffHunk
	let actions: DiffViewer.HunkActions?

	var body: some View {
		HStack {
			Text(hunk.header)
				.font(.system(.caption, design: .monospaced))
				.foregroundStyle(.secondary)

			Spacer()

			if let actions {
				HStack(spacing: 6) {
					if actions.isStaged {
						HunkActionButton(title: "Unstage") { actions.onUnstage(hunk) }
					}
					else {
						HunkActionButton(title: "Stage") { actions.onStage(hunk) }
						HunkActionButton(title: "Discard") { actions.onDiscard(hunk) }
					}
				}
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(
			UnevenRoundedRectangle(
				topLeadingRadius: HunkCard.cornerRadius,
				topTrailingRadius: HunkCard.cornerRadius
			)
			.fill(HunkCard.headerFill)
		)
		// Border: the fill is inset by the border width inside a slightly larger shape of the
		// border colour. Concentric corners need the outer radius to grow by the same amount.
		.padding([.horizontal, .top], HunkCard.borderWidth)
		.background(
			UnevenRoundedRectangle(
				topLeadingRadius: HunkCard.cornerRadius + HunkCard.borderWidth,
				topTrailingRadius: HunkCard.cornerRadius + HunkCard.borderWidth
			)
			.fill(HunkCard.border)
		)
		.padding(.horizontal, HunkCard.horizontalInset)
		.padding(.top, HunkCard.verticalGap)
	}
}

// MARK: - Footer

/// Closes the card at the bottom with the rounded corners.
struct HunkFooterView: View {
	var body: some View {
		UnevenRoundedRectangle(
			bottomLeadingRadius: HunkCard.cornerRadius,
			bottomTrailingRadius: HunkCard.cornerRadius
		)
		.fill(HunkCard.fill)
		.frame(height: HunkCard.cornerRadius)
		.padding([.horizontal, .bottom], HunkCard.borderWidth)
		.background(
			UnevenRoundedRectangle(
				bottomLeadingRadius: HunkCard.cornerRadius + HunkCard.borderWidth,
				bottomTrailingRadius: HunkCard.cornerRadius + HunkCard.borderWidth
			)
			.fill(HunkCard.border)
		)
		.padding(.horizontal, HunkCard.horizontalInset)
		.padding(.bottom, HunkCard.verticalGap)
	}
}

// MARK: - Row

/// Card fill and side borders for one diff line. Two flat colour backgrounds and two paddings
/// per row: this runs for every visible line, so it stays cheaper than shapes or overlays.
private struct HunkCardRowModifier: ViewModifier {
	func body(content: Content) -> some View {
		content
			.background(HunkCard.fill)
			.padding(.horizontal, HunkCard.borderWidth)
			.background(HunkCard.border)
			.padding(.horizontal, HunkCard.horizontalInset)
	}
}

extension View {
	func hunkCardRow() -> some View {
		modifier(HunkCardRowModifier())
	}
}
