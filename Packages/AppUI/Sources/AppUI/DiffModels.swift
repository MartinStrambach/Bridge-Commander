import Foundation

// MARK: - File Change Status

public enum FileChangeStatus: String, Equatable, Sendable {
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

public struct FileChange: Identifiable, Equatable, Sendable {
	public let id: String
	public let path: String
	public let status: FileChangeStatus

	public var fileName: String {
		(path as NSString).lastPathComponent
	}

	public var directoryPath: String {
		(path as NSString).deletingLastPathComponent
	}

	public init(id: String, path: String, status: FileChangeStatus) {
		self.id = id
		self.path = path
		self.status = status
	}
}

// MARK: - Diff Line

public struct DiffLine: Identifiable, Equatable, Sendable {
	public enum LineType: Equatable, Sendable {
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

	public init(id: String, rawLine: String, type: LineType, content: String, oldLineNumber: Int?, newLineNumber: Int?) {
		self.id = id
		self.rawLine = rawLine
		self.type = type
		self.content = content
		self.oldLineNumber = oldLineNumber
		self.newLineNumber = newLineNumber
	}
}

// MARK: - Diff Hunk

public struct DiffHunk: Identifiable, Equatable, Sendable {
	public let id: String
	public let header: String
	public let lines: [DiffLine]

	public init(id: String, header: String, lines: [DiffLine]) {
		self.id = id
		self.header = header
		self.lines = lines
	}
}

// MARK: - File Diff

public struct FileDiff: Equatable, Sendable {
	public let fileChange: FileChange
	public let hunks: [DiffHunk]
	public let isBinary: Bool

	public init(fileChange: FileChange, hunks: [DiffHunk], isBinary: Bool) {
		self.fileChange = fileChange
		self.hunks = hunks
		self.isBinary = isBinary
	}
}
