import Testing

@testable import GitCore

struct ImageDiffSidesTests {

	private let path = "Assets/logo.png"

	// MARK: - Unstaged: index → working tree

	@Test
	func unstagedModifiedComparesIndexToWorkingTree() {
		let sides = ImageDiffSides.resolve(for: FileChange(path: path, status: .modified), isStaged: false)

		#expect(sides == ImageDiffSides(old: .index(path: path), new: .workingTree(path: path)))
	}

	@Test
	func untrackedImageHasOnlyAWorkingTreeSide() {
		let sides = ImageDiffSides.resolve(for: FileChange(path: path, status: .untracked), isStaged: false)

		#expect(sides == ImageDiffSides(old: nil, new: .workingTree(path: path)))
	}

	@Test
	func unstagedDeletionHasOnlyAnIndexSide() {
		let sides = ImageDiffSides.resolve(for: FileChange(path: path, status: .deleted), isStaged: false)

		#expect(sides == ImageDiffSides(old: .index(path: path), new: nil))
	}

	// MARK: - Staged: HEAD → index

	@Test
	func stagedModifiedComparesHeadToIndex() {
		let sides = ImageDiffSides.resolve(for: FileChange(path: path, status: .modified), isStaged: true)

		#expect(sides == ImageDiffSides(old: .head(path: path), new: .index(path: path)))
	}

	@Test
	func stagedAdditionHasOnlyAnIndexSide() {
		let sides = ImageDiffSides.resolve(for: FileChange(path: path, status: .added), isStaged: true)

		#expect(sides == ImageDiffSides(old: nil, new: .index(path: path)))
	}

	@Test
	func stagedDeletionHasOnlyAHeadSide() {
		let sides = ImageDiffSides.resolve(for: FileChange(path: path, status: .deleted), isStaged: true)

		#expect(sides == ImageDiffSides(old: .head(path: path), new: nil))
	}

	@Test
	func stagedRenameReadsTheOldSideFromThePreviousPath() {
		let file = FileChange(path: "Assets/new-logo.png", status: .renamed, oldPath: "Assets/old-logo.png")
		let sides = ImageDiffSides.resolve(for: file, isStaged: true)

		#expect(sides == ImageDiffSides(old: .head(path: "Assets/old-logo.png"), new: .index(path: "Assets/new-logo.png")))
	}

	// MARK: - Not applicable

	@Test
	func nonImageFilesResolveToNothing() {
		#expect(ImageDiffSides.resolve(for: FileChange(path: "Sources/App.swift", status: .modified), isStaged: false) == nil)
		#expect(ImageDiffSides.resolve(for: FileChange(path: "Assets/font.ttf", status: .modified), isStaged: true) == nil)
	}

	@Test
	func conflictedImagesResolveToNothing() {
		#expect(ImageDiffSides.resolve(for: FileChange(path: path, status: .conflicted), isStaged: false) == nil)
	}
}
