import AppKit
import Foundation
import SwiftTerm

/// Dropping files onto a pane pastes their paths at the prompt.
extension ClaudeAwareTerminalView {
	override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
			? .copy
			: []
	}

	override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let pb = sender.draggingPasteboard
		guard
			let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
			!urls.isEmpty
		else {
			return false
		}

		// A paste, not typed input: bracketed when the program asked for bracketed paste, so Claude
		// Code takes the paths as one dropped item. It still reaches `send(source:data:)`, which
		// releases a waiting pane like a keystroke.
		pasteText(urls.map(\.path.shellEscaped).joined(separator: " "))
		return true
	}
}

private extension String {
	/// Backslash-escapes shell-special characters so the path can be used as-is
	/// at the command line without surrounding quotes.
	/// e.g. `/foo bar` → `/foo\ bar`, `/it's` → `/it\'s`
	var shellEscaped: String {
		let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-_.,=@:+"))
		return unicodeScalars.reduce(into: "") { result, scalar in
			if safe.contains(scalar) {
				result.append(Character(scalar))
			}
			else {
				result += "\\\(Character(scalar))"
			}
		}
	}
}
