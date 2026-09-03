import Foundation

/// Where one side of an image comparison is read from.
public nonisolated enum ImageDiffSource: Equatable, Sendable {
	/// The committed blob at `HEAD:<path>`.
	case head(path: String)
	/// The staged blob at `:<path>`.
	case index(path: String)
	/// The file as it currently sits on disk.
	case workingTree(path: String)
}

/// Resolves which two versions of an image a staged or unstaged change compares.
///
/// The unstaged list compares index → working tree; the staged list compares HEAD → index.
/// A side is nil when the file does not exist there: an added image has no old side and a
/// deleted image has no new side.
public nonisolated struct ImageDiffSides: Equatable, Sendable {
	public let old: ImageDiffSource?
	public let new: ImageDiffSource?

	public init(old: ImageDiffSource?, new: ImageDiffSource?) {
		self.old = old
		self.new = new
	}

	/// Returns nil when the file is not an image, or when its state has no single pair of
	/// versions to compare (a conflicted file has no stage-0 index entry).
	public static func resolve(for file: FileChange, isStaged: Bool) -> ImageDiffSides? {
		guard ImageFileDetector.isImage(path: file.path) else {
			return nil
		}

		// Renames record the pre-change path separately; every other status has one path.
		let oldPath = file.oldPath ?? file.path

		switch file.status {
		case .conflicted:
			return nil

		case .added,
		     .untracked:
			return ImageDiffSides(
				old: nil,
				new: isStaged ? .index(path: file.path) : .workingTree(path: file.path)
			)

		case .deleted:
			return ImageDiffSides(
				old: isStaged ? .head(path: oldPath) : .index(path: oldPath),
				new: nil
			)

		case .modified,
		     .renamed,
		     .copied,
		     .typeChanged:
			return isStaged
				? ImageDiffSides(old: .head(path: oldPath), new: .index(path: file.path))
				: ImageDiffSides(old: .index(path: oldPath), new: .workingTree(path: file.path))
		}
	}
}
