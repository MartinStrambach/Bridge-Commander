import Foundation
import ProcessExecution

/// Loads the raw bytes of both versions of a changed image so the staging view can render them
/// side by side instead of showing a binary placeholder.
public nonisolated enum GitImageDiffLoader {

	/// Images above this size stay an opaque binary change: the bytes would otherwise be held in
	/// memory for the whole time the file is selected.
	static let maxImageSize = 20 * 1024 * 1024

	public static func load(at repositoryPath: String, file: FileChange, isStaged: Bool) async -> ImageDiff? {
		guard let sides = ImageDiffSides.resolve(for: file, isStaged: isStaged) else {
			return nil
		}

		async let oldTask = read(sides.old, at: repositoryPath)
		async let newTask = read(sides.new, at: repositoryPath)
		let (old, new) = await (oldTask, newTask)

		// A side that should exist but could not be read leaves nothing to compare against, so
		// fall back to the plain binary placeholder rather than show half a diff.
		guard (sides.old == nil) == (old == nil), (sides.new == nil) == (new == nil) else {
			return nil
		}
		guard old != nil || new != nil else {
			return nil
		}

		return ImageDiff(oldImageData: old, newImageData: new)
	}

	// MARK: - Private Helpers

	private static func read(_ source: ImageDiffSource?, at repositoryPath: String) async -> Data? {
		switch source {
		case nil:
			nil
		case let .head(path):
			await readBlob("HEAD:\(path)", at: repositoryPath)
		case let .index(path):
			await readBlob(":\(path)", at: repositoryPath)
		case let .workingTree(path):
			readWorkingTreeFile(path, at: repositoryPath)
		}
	}

	/// `cat-file blob` prints the stored bytes verbatim, unlike `show`, which may run textconv
	/// filters configured for the path.
	private static func readBlob(_ object: String, at repositoryPath: String) async -> Data? {
		let result = await ProcessRunner.runGit(arguments: ["cat-file", "blob", object], at: repositoryPath)
		guard result.success, !result.output.isEmpty, result.output.count <= maxImageSize else {
			return nil
		}

		return result.output
	}

	private static func readWorkingTreeFile(_ path: String, at repositoryPath: String) -> Data? {
		let fullPath = (repositoryPath as NSString).appendingPathComponent(path)
		guard
			let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
			let size = attributes[.size] as? Int,
			size > 0,
			size <= maxImageSize
		else {
			return nil
		}

		return FileManager.default.contents(atPath: fullPath)
	}
}
