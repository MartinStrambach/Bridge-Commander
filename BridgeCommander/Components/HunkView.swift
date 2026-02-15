import SwiftUI

struct HunkView: View {
	let hunk: DiffHunk
	let isStaged: Bool
	let onStage: () -> Void
	let onUnstage: () -> Void
	let onDiscard: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// Hunk Header with Actions
			HStack {
				Text(hunk.header)
					.font(.system(.caption, design: .monospaced))
					.foregroundStyle(.secondary)

				Spacer()

				// Hunk Actions
				HStack(spacing: 6) {
					if !isStaged {
						HunkActionButton(title: "Stage", action: onStage)
					}

					if isStaged {
						HunkActionButton(title: "Unstage", action: onUnstage)
					}

					if !isStaged {
						HunkActionButton(title: "Discard", action: onDiscard)
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color(nsColor: .controlBackgroundColor))

			// Hunk Lines
			ForEach(Array(hunk.lines.enumerated()), id: \.element.id) { index, line in
				let lineNumbers = calculateLineNumbers(for: index)
				DiffLineView(
					line: line,
					oldLineNumber: lineNumbers.oldLine,
					newLineNumber: lineNumbers.newLine
				)
			}
		}
		.background(Color(nsColor: .textBackgroundColor))
		.cornerRadius(6)
		.overlay(
			RoundedRectangle(cornerRadius: 6)
				.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
		)
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
	}

	private func calculateLineNumbers(for index: Int) -> (oldLine: Int?, newLine: Int?) {
		var oldLine = hunk.oldStart
		var newLine = hunk.newStart

		for i in 0 ..< index {
			let line = hunk.lines[i]
			switch line.type {
			case .context:
				oldLine += 1
				newLine += 1

			case .deletion:
				oldLine += 1

			case .addition:
				newLine += 1
			}
		}

		let currentLine = hunk.lines[index]
		switch currentLine.type {
		case .context:
			return (oldLine, newLine)
		case .deletion:
			return (oldLine, nil)
		case .addition:
			return (nil, newLine)
		}
	}
}
