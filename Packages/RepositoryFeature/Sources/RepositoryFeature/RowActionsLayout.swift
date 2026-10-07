import SwiftUI

/// Lays the row's smaller actions (menus and icon buttons) out on one line when the row has room
/// for it, and on two otherwise, so they give up width before the branch title does.
///
/// A `Layout` rather than a `ViewThatFits` over two arrangements: the menus carry their own
/// alerts and confirmation dialogs, and a second copy of them would be a second presenter.
///
/// Unspecified or wide-enough widths get one line; anything narrower gets the two-line split
/// whose wider line is narrowest, which is also what the layout reports as its minimum width.
struct RowActionsLayout: Layout {
	var spacing: CGFloat = 8
	var lineSpacing: CGFloat = 6

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
		return size(of: lines(for: sizes, width: proposal.width), sizes: sizes)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
		let lines = lines(for: sizes, width: bounds.width)
		var y = bounds.midY - size(of: lines, sizes: sizes).height / 2
		for line in lines {
			let lineHeight = height(of: line, sizes: sizes)
			var x = bounds.minX
			for index in line {
				subviews[index].place(
					at: CGPoint(x: x, y: y + lineHeight / 2),
					anchor: .leading,
					proposal: ProposedViewSize(sizes[index])
				)
				x += sizes[index].width + spacing
			}
			y += lineHeight + lineSpacing
		}
	}

	private func lines(for sizes: [CGSize], width: CGFloat?) -> [Range<Int>] {
		Self.lines(widths: sizes.map(\.width), spacing: spacing, available: width)
	}

	/// Index ranges of the lines `widths` are laid out on within `available` points.
	static func lines(widths: [CGFloat], spacing: CGFloat, available: CGFloat?) -> [Range<Int>] {
		let all = widths.indices
		// Half a point of slack: the width handed back in `placeSubviews` is the one reported
		// from `sizeThatFits`, and rounding must not flip the arrangement between the two.
		guard widths.count > 1,
		      let available,
		      lineWidth(all, widths: widths, spacing: spacing) > available + 0.5
		else {
			return [all]
		}
		func twoLineWidth(splitAt split: Int) -> CGFloat {
			max(
				lineWidth(0 ..< split, widths: widths, spacing: spacing),
				lineWidth(split ..< widths.count, widths: widths, spacing: spacing)
			)
		}
		let split = (1 ..< widths.count).min { twoLineWidth(splitAt: $0) < twoLineWidth(splitAt: $1) } ?? 1
		return [0 ..< split, split ..< widths.count]
	}

	private static func lineWidth(_ line: Range<Int>, widths: [CGFloat], spacing: CGFloat) -> CGFloat {
		line.reduce(0) { $0 + widths[$1] } + spacing * CGFloat(max(line.count - 1, 0))
	}

	private func width(of line: Range<Int>, sizes: [CGSize]) -> CGFloat {
		Self.lineWidth(line, widths: sizes.map(\.width), spacing: spacing)
	}

	private func height(of line: Range<Int>, sizes: [CGSize]) -> CGFloat {
		line.map { sizes[$0].height }.max() ?? 0
	}

	private func size(of lines: [Range<Int>], sizes: [CGSize]) -> CGSize {
		CGSize(
			width: lines.map { width(of: $0, sizes: sizes) }.max() ?? 0,
			height: lines.reduce(0) { $0 + height(of: $1, sizes: sizes) }
				+ lineSpacing * CGFloat(max(lines.count - 1, 0))
		)
	}
}
