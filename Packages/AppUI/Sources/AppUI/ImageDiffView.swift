import AppKit
import SwiftUI

/// Renders a changed image as "Before" and "After" panes side by side. An added or deleted image
/// shows a single pane. Each pane draws the image at its native size (never upscaled) on a
/// checkerboard so transparency is visible, with pixel dimensions and byte size underneath.
public struct ImageDiffView: View {
	public let imageDiff: ImageDiff

	/// nil until the first decode has run, so panes can distinguish "still decoding" from
	/// "bytes are not a decodable image".
	@State private var decoded: DecodedImages?

	public init(imageDiff: ImageDiff) {
		self.imageDiff = imageDiff
	}

	public var body: some View {
		HStack(alignment: .top, spacing: 16) {
			if let data = imageDiff.oldImageData {
				ImageDiffPane(
					title: "Before",
					role: .deletion,
					byteCount: data.count,
					content: paneContent(for: decoded?.old)
				)
			}

			if let data = imageDiff.newImageData {
				ImageDiffPane(
					title: "After",
					role: .addition,
					byteCount: data.count,
					content: paneContent(for: decoded?.new)
				)
			}
		}
		.frame(maxWidth: .infinity)
		.padding()
		.task(id: imageDiff) {
			// NSImage parses only the header here; pixel decoding happens lazily on first draw and
			// is cached by the image rep, which is why the result lives in state rather than being
			// rebuilt on every render.
			decoded = DecodedImages(
				old: imageDiff.oldImageData.flatMap(DecodedImage.init),
				new: imageDiff.newImageData.flatMap(DecodedImage.init)
			)
		}
	}

	private func paneContent(for image: DecodedImage?) -> ImageDiffPane.Content {
		guard decoded != nil else {
			return .decoding
		}

		guard let image else {
			return .unavailable
		}

		return .image(image)
	}
}

// MARK: - Decoded Images

private struct DecodedImages {
	let old: DecodedImage?
	let new: DecodedImage?
}

private struct DecodedImage {
	let image: NSImage
	/// Pixel dimensions from the bitmap rep; `NSImage.size` is in points and honours DPI metadata,
	/// so a 2x asset would otherwise report half its real size.
	let pixelSize: CGSize?

	init?(data: Data) {
		guard let image = NSImage(data: data) else {
			return nil
		}

		self.image = image
		if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
			self.pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
		}
		else {
			self.pixelSize = nil
		}
	}
}

// MARK: - Pane

private struct ImageDiffPane: View {
	enum Role {
		case addition
		case deletion

		var color: Color {
			switch self {
			case .addition: Color(red: 0.0, green: 0.5, blue: 0.0)
			case .deletion: Color(red: 0.7, green: 0.0, blue: 0.0)
			}
		}
	}

	enum Content {
		case decoding
		case unavailable
		case image(DecodedImage)
	}

	let title: String
	let role: Role
	let byteCount: Int
	let content: Content

	/// Tall images are scaled down to this height; short ones keep their native height.
	private static let maxImageHeight: CGFloat = 560
	/// Keeps tiny icons from collapsing the pane into a sliver.
	private static let minPaneHeight: CGFloat = 96

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			header

			switch content {
			case .decoding:
				placeholder {
					ProgressView()
						.controlSize(.small)
				}

			case .unavailable:
				placeholder {
					VStack(spacing: 6) {
						Image(systemName: "photo.badge.exclamationmark")
							.font(.system(size: 28))
							.foregroundStyle(.secondary)

						Text("Preview unavailable")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}

			case let .image(decoded):
				Image(nsImage: decoded.image)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.background(CheckerboardBackground())
					.clipShape(RoundedRectangle(cornerRadius: 4))
					.overlay(
						RoundedRectangle(cornerRadius: 4)
							.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
					)
					.frame(maxWidth: .infinity)
					.frame(height: paneHeight(for: decoded))
			}
		}
		.frame(maxWidth: .infinity)
	}

	private var header: some View {
		HStack(spacing: 8) {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(role.color)

			Spacer()

			Text(caption)
				.font(.caption)
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
	}

	private var caption: String {
		let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
		guard case let .image(decoded) = content, let pixels = decoded.pixelSize else {
			return size
		}

		return "\(Int(pixels.width)) × \(Int(pixels.height)) px · \(size)"
	}

	/// A definite height keeps the aspect-fit image deterministic inside the lazy stack, where
	/// the vertical proposal is otherwise unbounded. The image is never scaled above its native
	/// point size.
	private func paneHeight(for decoded: DecodedImage) -> CGFloat {
		min(max(decoded.image.size.height, Self.minPaneHeight), Self.maxImageHeight)
	}

	private func placeholder(@ViewBuilder _ label: () -> some View) -> some View {
		label()
			.frame(maxWidth: .infinity)
			.frame(height: Self.minPaneHeight)
			.background(
				RoundedRectangle(cornerRadius: 4)
					.fill(Color(nsColor: .textBackgroundColor))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 4)
					.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
			)
	}
}

// MARK: - Checkerboard

/// Alternating squares behind an image so transparent regions read as transparent rather than
/// blending into the panel background.
private struct CheckerboardBackground: View {
	private static let cellSize: CGFloat = 8

	var body: some View {
		Canvas { context, size in
			let cell = Self.cellSize
			var darkCells = Path()
			var row = 0
			var y: CGFloat = 0
			while y < size.height {
				var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
				while x < size.width {
					darkCells.addRect(CGRect(x: x, y: y, width: cell, height: cell))
					x += cell * 2
				}
				y += cell
				row += 1
			}
			context.fill(darkCells, with: .color(.primary.opacity(0.08)))
		}
		.background(Color(nsColor: .textBackgroundColor))
	}
}
