import AppUI
import GitCore

extension GitCore.FileChangeStatus {
	func toAppUI() -> AppUI.FileChangeStatus {
		switch self {
		case .added: .added
		case .modified: .modified
		case .deleted: .deleted
		case .renamed: .renamed
		case .copied: .copied
		case .untracked: .untracked
		case .typeChanged: .typeChanged
		case .conflicted: .conflicted
		}
	}
}

extension GitCore.FileChange {
	func toAppUI() -> AppUI.FileChange {
		AppUI.FileChange(id: id, path: path, status: status.toAppUI())
	}
}

extension GitCore.DiffLine {
	func toAppUI() -> AppUI.DiffLine {
		let lineType: AppUI.DiffLine.LineType = switch type {
		case .context: .context
		case .addition: .addition
		case .deletion: .deletion
		}
		return AppUI.DiffLine(
			id: id,
			rawLine: rawLine,
			type: lineType,
			content: content,
			oldLineNumber: oldLineNumber,
			newLineNumber: newLineNumber,
			inlineChanges: inlineChanges
		)
	}
}

extension GitCore.DiffHunk {
	func toAppUI() -> AppUI.DiffHunk {
		AppUI.DiffHunk(id: id, header: header, lines: lines.map { $0.toAppUI() })
	}
}

extension GitCore.FileDiff {
	func toAppUI() -> AppUI.FileDiff {
		AppUI.FileDiff(fileChange: fileChange.toAppUI(), hunks: hunks.map { $0.toAppUI() }, isBinary: isBinary)
	}
}
