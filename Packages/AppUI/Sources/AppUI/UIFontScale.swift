import AppKit
import SwiftUI

/// Scaling of the app's own text, driven by the UI text size setting.
///
/// macOS ignores `dynamicTypeSize` — a text style renders at one fixed size whatever it is set to —
/// so the app scales its text itself: views ask for `.scaledFont(.caption)` instead of
/// `.font(.caption)`, and the modifier turns the style into a point size times `uiFontScale`.
public enum UIFontScale {

	/// The point size macOS draws each text style at (`NSFont.preferredFont(forTextStyle:)`, which
	/// has not changed across releases). Spelled out because SwiftUI offers no way to ask a
	/// `Font.TextStyle` for its size.
	public static func pointSize(of style: Font.TextStyle) -> CGFloat {
		switch style {
		case .largeTitle: 26
		case .title: 22
		case .title2: 17
		case .title3: 15
		case .headline: 13
		case .subheadline: 11
		case .body: 13
		case .callout: 12
		case .footnote: 10
		case .caption: 10
		case .caption2: 10
		@unknown default: 13
		}
	}

	/// The weight a style carries on its own; on macOS only `.headline` is bold.
	static func defaultWeight(of style: Font.TextStyle) -> Font.Weight? {
		style == .headline ? .bold : nil
	}

	/// The font for a text style at a scale.
	///
	/// At a scale of 1 this is the text style itself, not a point size that happens to match, so an
	/// install that never touches the setting renders exactly as it did before the setting existed.
	public static func font(
		_ style: Font.TextStyle,
		design: Font.Design? = nil,
		weight: Font.Weight? = nil,
		scale: CGFloat
	) -> Font {
		guard scale != 1 else {
			return .system(style, design: design, weight: weight)
		}
		return .system(
			size: pointSize(of: style) * scale,
			weight: weight ?? defaultWeight(of: style),
			design: design
		)
	}
}

extension UIFontScale {
	/// The point size AppKit draws a control's title at for a control size.
	static func controlPointSize(for controlSize: ControlSize) -> CGFloat {
		let appKitSize: NSControl.ControlSize = switch controlSize {
		case .mini: .mini
		case .small: .small
		case .regular: .regular
		case .large: .large
		case .extraLarge: .extraLarge
		@unknown default: .regular
		}
		return NSFont.systemFontSize(for: appKitSize)
	}
}

public extension EnvironmentValues {
	/// How much larger (or smaller) than the system's sizes the app's text is drawn. 1 = unchanged.
	@Entry
	var uiFontScale: CGFloat = 1
}

private struct ScaledTextStyleFont: ViewModifier {
	let style: Font.TextStyle
	let design: Font.Design?
	let weight: Font.Weight?

	@Environment(\.uiFontScale)
	private var scale

	func body(content: Content) -> some View {
		content.font(UIFontScale.font(style, design: design, weight: weight, scale: scale))
	}
}

private struct ScaledSizeFont: ViewModifier {
	let size: CGFloat
	let design: Font.Design?
	let weight: Font.Weight?

	@Environment(\.uiFontScale)
	private var scale

	func body(content: Content) -> some View {
		content.font(.system(size: size * scale, weight: weight, design: design))
	}
}

public extension View {
	/// `.font(.system(style, design:, weight:))`, scaled by the UI text size setting.
	func scaledFont(
		_ style: Font.TextStyle,
		design: Font.Design? = nil,
		weight: Font.Weight? = nil
	) -> some View {
		modifier(ScaledTextStyleFont(style: style, design: design, weight: weight))
	}

	/// `.font(.system(size:, weight:, design:))`, scaled by the UI text size setting.
	func scaledFont(
		size: CGFloat,
		weight: Font.Weight? = nil,
		design: Font.Design? = nil
	) -> some View {
		modifier(ScaledSizeFont(size: size, design: design, weight: weight))
	}

	/// Draws the app's text at `scale` times the system's sizes: views using `scaledFont` read it,
	/// and text with no font of its own gets a scaled body font.
	///
	/// At a scale of 1 no font is set at all (`nil` is the environment's default), so controls keep
	/// the font they choose for themselves. One modifier chain either way, not an `if`: a branch
	/// would change the identity of everything below it, resetting the window's state (and its
	/// terminal panes) whenever the setting crossed 1.
	func uiFontScale(_ scale: CGFloat) -> some View {
		environment(\.uiFontScale, scale)
			.font(scale == 1 ? nil : .system(size: UIFontScale.pointSize(of: .body) * scale))
	}
}

/// `.automatic` / `.bordered` / `.borderedProminent` with the title scaled by the UI text size
/// setting.
///
/// A push or bordered button is drawn by AppKit and ignores any font it inherits: `.font` on the
/// button or an ancestor leaves its title at the control size's own size (measured 2026-10-06). It
/// only takes a font set *inside* its label, so this style puts one there — the control size's
/// title size times `uiFontScale` — and the button grows to fit it. Plain and borderless buttons
/// need none of this; they follow the inherited font.
///
/// At a scale of 1 it is the native style untouched. Rebuilding the button from the
/// configuration's role and trigger keeps keyboard shortcuts applied to it working, Return and
/// Escape included.
public struct ScaledButtonStyle: PrimitiveButtonStyle {
	enum Base {
		case automatic
		case bordered
		case borderedProminent
	}

	let base: Base

	@Environment(\.uiFontScale)
	private var scale

	@Environment(\.controlSize)
	private var controlSize

	public func makeBody(configuration: Configuration) -> some View {
		if scale == 1 {
			styled(Button(configuration))
		}
		else {
			styled(
				Button(role: configuration.role, action: configuration.trigger) {
					configuration.label
						.font(.system(size: UIFontScale.controlPointSize(for: controlSize) * scale))
				}
			)
		}
	}

	@ViewBuilder
	private func styled(_ button: some View) -> some View {
		switch base {
		case .automatic: button.buttonStyle(.automatic)
		case .bordered: button.buttonStyle(.bordered)
		case .borderedProminent: button.buttonStyle(.borderedProminent)
		}
	}
}

public extension PrimitiveButtonStyle where Self == ScaledButtonStyle {
	/// The default push button, scaled by the UI text size setting. Set it on a dialog's button row
	/// (or any container) for buttons that have no style of their own.
	static var scaledAutomatic: Self {
		ScaledButtonStyle(base: .automatic)
	}

	/// `.bordered`, scaled by the UI text size setting. Use instead of `.bordered`.
	static var scaledBordered: Self {
		ScaledButtonStyle(base: .bordered)
	}

	/// `.borderedProminent`, scaled by the UI text size setting. Use instead of `.borderedProminent`.
	static var scaledBorderedProminent: Self {
		ScaledButtonStyle(base: .borderedProminent)
	}
}
