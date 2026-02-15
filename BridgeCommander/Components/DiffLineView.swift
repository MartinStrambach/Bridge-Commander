import SwiftUI

struct DiffLineView: View {
	let line: DiffLine
	let oldLineNumber: Int?
	let newLineNumber: Int?

	private var linePrefix: String {
		switch line.type {
		case .addition: "+"
		case .deletion: "-"
		case .context: " "
		}
	}

	private var lineColor: Color {
		switch line.type {
		case .addition: Color(red: 0.0, green: 0.5, blue: 0.0)
		case .deletion: Color(red: 0.7, green: 0.0, blue: 0.0)
		case .context: .secondary
		}
	}

	private var backgroundColor: Color {
		switch line.type {
		case .addition:
			Color(red: 0.85, green: 0.95, blue: 0.85)
		case .deletion:
			Color(red: 0.95, green: 0.85, blue: 0.85)
		case .context:
			Color.clear
		}
	}

	var body: some View {
		HStack(spacing: 0) {
			// Old line number
			Text(oldLineNumber.map { String($0) } ?? "")
				.frame(width: 35, alignment: .trailing)
				.foregroundStyle(.secondary.opacity(0.6))
				.font(.system(.caption, design: .monospaced))
				.padding(.vertical, 1)
				.padding(.leading, 8)

			// New line number
			Text(newLineNumber.map { String($0) } ?? "")
				.frame(width: 35, alignment: .trailing)
				.foregroundStyle(.secondary.opacity(0.6))
				.font(.system(.caption, design: .monospaced))
				.padding(.vertical, 1)
				.padding(.trailing, 8)

			// Line prefix and content with colored background
			HStack(spacing: 0) {
				// Line prefix indicator
				Text(linePrefix)
					.frame(width: 20, alignment: .center)
					.foregroundStyle(lineColor)

				// Line content
				Text(line.content)
					.font(.system(.body, design: .monospaced))
					.foregroundStyle(lineColor)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.padding(.vertical, 1)
			.padding(.trailing, 8)
			.background(backgroundColor)
		}
	}
}
