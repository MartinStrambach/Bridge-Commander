import SwiftUI

/// The repository row's buttons: a rounded tile with a soft fill — tinted when the button carries a
/// status colour (a passing pipeline, a delete) — that brightens under the pointer and dips when
/// pressed. Drawn by SwiftUI rather than AppKit's bezel, so the icon buttons, the large tool
/// buttons and the menus beside them (`menuTile()`) share one shape.
public struct TileButtonStyle: ButtonStyle {
	private let tint: Color?
	private let cornerRadius: CGFloat

	public init(tint: Color? = nil, cornerRadius: CGFloat = 7) {
		self.tint = tint
		self.cornerRadius = cornerRadius
	}

	public func makeBody(configuration: Configuration) -> some View {
		TileButtonBody(configuration: configuration, tint: tint, cornerRadius: cornerRadius)
	}
}

public extension ButtonStyle where Self == TileButtonStyle {
	static func tile(tint: Color? = nil, cornerRadius: CGFloat = 7) -> TileButtonStyle {
		TileButtonStyle(tint: tint, cornerRadius: cornerRadius)
	}
}

/// A view rather than the style's body, so it can hold the hover state.
private struct TileButtonBody: View {
	let configuration: ButtonStyleConfiguration
	let tint: Color?
	let cornerRadius: CGFloat

	@Environment(\.isEnabled)
	private var isEnabled

	@State
	private var isHovered = false

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
		configuration.label
			.background(TileFill.color(tint: tint), in: shape)
			.background(Color.primary.opacity(highlightOpacity), in: shape)
			.overlay {
				shape.strokeBorder((tint ?? .primary).opacity(isHovered ? 0.22 : 0))
			}
			.contentShape(shape)
			.scaleEffect(configuration.isPressed ? 0.95 : 1)
			.opacity(isEnabled ? 1 : 0.45)
			.onHover { isHovered = $0 && isEnabled }
			.animation(.easeOut(duration: 0.12), value: isHovered)
			.animation(.easeOut(duration: 0.08), value: configuration.isPressed)
	}

	private var highlightOpacity: Double {
		if configuration.isPressed {
			return 0.12
		}
		return isHovered ? 0.06 : 0
	}
}

/// The tile's resting fill, shared with `menuTile()` so a menu sits on the same tile as a button.
enum TileFill {
	static func color(tint: Color?) -> Color {
		if let tint {
			return tint.opacity(0.14)
		}
		return Color.primary.opacity(0.06)
	}
}

public extension View {
	/// Sets a `.borderlessButton` menu (or a progress pill standing in for one) on the same tile as
	/// `TileButtonStyle`. AppKit draws the menu itself, so only its background can match: the tile's
	/// padding is not part of the click target.
	func menuTile(tint: Color? = nil) -> some View {
		padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(TileFill.color(tint: tint), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
	}
}

#Preview {
	HStack(spacing: 8) {
		Button {} label: {
			Image(systemName: "folder").frame(width: 28, height: 28)
		}
		.buttonStyle(.tile())
		.foregroundStyle(.secondary)
		Button {} label: {
			Image(systemName: "checkmark.circle.fill").frame(width: 28, height: 28)
		}
		.buttonStyle(.tile(tint: .green))
		.foregroundStyle(.green)
		Menu("Git Actions") {}
			.menuStyle(.borderlessButton)
			.fixedSize()
			.menuTile()
	}
	.padding()
}
