import Foundation

/// Recognises git's marker for a binary change in `git diff` output.
///
/// Git prints `Binary files a/<path> and b/<path> differ` (or `/dev/null` for one side) at
/// column 0 in place of hunks. Content lines always carry a `+`, `-` or space prefix, so a line
/// starting with the marker can only have come from git itself, never from the file's text.
/// A plain substring search would misclassify any source file that mentions "Binary files".
public nonisolated enum GitBinaryDiffDetector {

	public static func isBinaryDiff(_ diffOutput: String) -> Bool {
		diffOutput
			.split(separator: "\n", omittingEmptySubsequences: true)
			.contains { line in
				line.hasPrefix("Binary files ") && line.hasSuffix(" differ")
			}
	}
}
