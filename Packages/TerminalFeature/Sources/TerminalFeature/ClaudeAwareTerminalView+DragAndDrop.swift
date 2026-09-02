import AppKit
import Foundation

/// Dropping files onto a pane types their paths at the prompt.
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

		let paths = urls.map(\.path.shellEscaped).joined(separator: " ")
		guard let bytes = paths.data(using: .utf8) else {
			return false
		}

		send(source: self, data: ArraySlice(bytes))
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
