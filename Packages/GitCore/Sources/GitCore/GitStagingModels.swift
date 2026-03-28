import Foundation

// MARK: - File Change Status

public enum FileChangeStatus: String, Equatable {
	case added = "A"
	case modified = "M"
	case deleted = "D"
	case renamed = "R"
	case copied = "C"
	case untracked = "?"
	case typeChanged = "T"
	case conflicted = "U"

	public var displayName: String {
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

	public var iconName: String {
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

public nonisolated struct FileChange: Identifiable, Equatable {
	public let id: String
	public let path: String
	public let status: FileChangeStatus
	public let oldPath: String? // For renames

	public var fileName: String {
		(path as NSString).lastPathComponent
	}

	public var directoryPath: String {
		(path as NSString).deletingLastPathComponent
	}

	public init(path: String, status: FileChangeStatus, oldPath: String? = nil) {
		self.id = path
		self.path = path
		self.status = status
		self.oldPath = oldPath
	}
}

// MARK: - Diff Hunk

public nonisolated struct DiffHunk: Identifiable, Equatable {
	public let id: String
	public let header: String // e.g., "@@ -1,5 +1,6 @@"
	public let oldStart: Int
	public let oldCount: Int
	public let newStart: Int
	public let newCount: Int
	public let lines: [DiffLine]

	public var patch: String {
		([header] + lines.map(\.rawLine)).joined(separator: "\n")
	}

	public init(header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
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

public nonisolated struct DiffLine: Identifiable, Equatable {
	public enum LineType: Equatable {
		case context
		case addition
		case deletion
	}

	public let id: String
	public let rawLine: String
	public let type: LineType
	public let content: String
	public let oldLineNumber: Int?
	public let newLineNumber: Int?

	public init(rawLine: String, id: String, oldLineNumber: Int?, newLineNumber: Int?) {
		self.id = id
		self.rawLine = rawLine
		self.oldLineNumber = oldLineNumber
		self.newLineNumber = newLineNumber

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

public nonisolated struct FileDiff: Equatable {
	public let fileChange: FileChange
	public let hunks: [DiffHunk]
	public let isBinary: Bool

	public var hasChanges: Bool {
		!hunks.isEmpty
	}

	public init(fileChange: FileChange, hunks: [DiffHunk], isBinary: Bool = false) {
		self.fileChange = fileChange
		self.hunks = hunks
		self.isBinary = isBinary
	}
}
