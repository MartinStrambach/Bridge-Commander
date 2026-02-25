import Foundation

// MARK: - File Change Status

enum FileChangeStatus: String, Equatable, Sendable {
	case added = "A"
	case modified = "M"
	case deleted = "D"
	case renamed = "R"
	case copied = "C"
	case untracked = "?"
	case typeChanged = "T"
	case conflicted = "U"

	var displayName: String {
		switch self {
		case .added: "Added"
		case .modified: "Modified"
		case .deleted: "Deleted"
		case .renamed: "Renamed"
		case .copied: "Copied"
		case .untracked: "Untracked"
		case .typeChanged: "Type Changed"
		case .conflicted: "Conflicted"
		}
	}

	var iconName: String {
		switch self {
		case .added: "plus.circle.fill"
		case .modified: "pencil.circle.fill"
		case .deleted: "minus.circle.fill"
		case .renamed: "arrow.triangle.2.circlepath.circle.fill"
		case .copied: "doc.on.doc.fill"
		case .untracked: "questionmark.circle.fill"
		case .typeChanged: "arrow.left.arrow.right.circle.fill"
		case .conflicted: "exclamationmark.triangle.fill"
		}
	}
}

// MARK: - File Change

nonisolated struct FileChange: Identifiable, Equatable, Sendable {
	let id: String
	let path: String
	let status: FileChangeStatus
	let oldPath: String? // For renames

	var fileName: String {
		(path as NSString).lastPathComponent
	}

	var directoryPath: String {
		(path as NSString).deletingLastPathComponent
	}

	init(path: String, status: FileChangeStatus, oldPath: String? = nil) {
		self.id = path
		self.path = path
		self.status = status
		self.oldPath = oldPath
	}
}

// MARK: - Diff Hunk

nonisolated struct DiffHunk: Identifiable, Equatable, Sendable {
	let id: String
	let header: String // e.g., "@@ -1,5 +1,6 @@"
	let oldStart: Int
	let oldCount: Int
	let newStart: Int
	let newCount: Int
	let lines: [DiffLine]

	var patch: String {
		([header] + lines.map(\.rawLine)).joined(separator: "\n")
	}

	init(header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
		self.id = header
		self.header = header
		self.oldStart = oldStart
		self.oldCount = oldCount
		self.newStart = newStart
		self.newCount = newCount
		self.lines = lines
	}
}

// MARK: - Diff Line

nonisolated struct DiffLine: Identifiable, Equatable, Sendable {
	enum LineType: Equatable, Sendable {
		case context
		case addition
		case deletion
	}

	let id: String
	let rawLine: String
	let type: LineType
	let content: String

	init(rawLine: String) {
		self.id = UUID().uuidString
		self.rawLine = rawLine

		if rawLine.hasPrefix("+") {
			self.type = .addition
			self.content = String(rawLine.dropFirst())
		}
		else if rawLine.hasPrefix("-") {
			self.type = .deletion
			self.content = String(rawLine.dropFirst())
		}
		else {
			self.type = .context
			self.content = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
		}
	}
}

// MARK: - File Diff

nonisolated struct FileDiff: Equatable, Sendable {
	let fileChange: FileChange
	let hunks: [DiffHunk]
	let isBinary: Bool

	var hasChanges: Bool {
		!hunks.isEmpty
	}

	init(fileChange: FileChange, hunks: [DiffHunk], isBinary: Bool = false) {
		self.fileChange = fileChange
		self.hunks = hunks
		self.isBinary = isBinary
	}
}
