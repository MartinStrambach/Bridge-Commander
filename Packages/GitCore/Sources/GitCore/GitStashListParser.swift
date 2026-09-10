import Foundation

// MARK: - Git Stash Entry

/// One entry of `git stash list`.
public struct GitStashEntry: Equatable, Sendable {
	/// The `stash@{n}` reference this entry can be applied or dropped by. Indices shift
	/// whenever an entry is added or removed, so a reference is only good for as long as
	/// the list it was parsed from.
	public let reference: String
	/// The branch the stash was taken on, or nil when git recorded no usable branch
	/// (a detached HEAD stashes as `(no branch)`).
	public let branch: String?
	/// Whatever follows the branch: the commit subject for a plain `git stash`, the
	/// custom text for `git stash push -m`.
	public let message: String

	public init(reference: String, branch: String?, message: String) {
		self.reference = reference
		self.branch = branch
		self.message = message
	}
}

// MARK: - Git Stash List Parser

/// Parses `git stash list` output into structured entries.
///
/// Detection used to be a substring search for `"WIP on \(branch):"` over the whole line,
/// which both missed nothing and matched too much: a stash message is free text, so
/// `git stash push -m "On main: fixup"` taken on `feature` looked like a stash on `main`.
/// Splitting the line into its fixed parts removes the guesswork, and carrying the
/// `stash@{n}` reference along lets apply/pop name the entry that was actually detected
/// instead of assuming it is `stash@{0}`.
public nonisolated enum GitStashListParser {

	/// Parses the output of `git stash list`.
	///
	/// Every line is `<reference>: <subject>`, where the subject is `WIP on <branch>: <sha> <text>`
	/// for a plain `git stash` and `On <branch>: <text>` for `git stash push -m`. Branch names
	/// cannot contain `:` (git rejects them), so the first colon after the prefix always ends
	/// the branch. Lines that don't fit the shape are kept with a nil branch rather than dropped,
	/// so an unexpected format can never make an existing stash invisible.
	/// - Parameter output: Raw `git stash list` output.
	/// - Returns: The entries in git's order, which is newest first.
	public static func parse(_ output: String) -> [GitStashEntry] {
		output.split(separator: "\n").compactMap { line in
			parseLine(String(line))
		}
	}

	/// The newest stash taken on `branch`.
	///
	/// `git stash list` is ordered newest first, so the first match is the entry a pop would
	/// naturally restore had every stash been taken on this branch.
	/// - Parameters:
	///   - branch: The branch to look for. An empty branch matches nothing — a row whose
	///     status hasn't been fetched yet must not claim the whole stash list.
	///   - entries: Entries as returned by `parse(_:)`.
	/// - Returns: The matching entry, or nil when the branch has no stash.
	public static func newestEntry(on branch: String, in entries: [GitStashEntry]) -> GitStashEntry? {
		guard !branch.isEmpty else {
			return nil
		}

		return entries.first { $0.branch == branch }
	}

	// MARK: - Private

	private static func parseLine(_ line: String) -> GitStashEntry? {
		let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
		guard
			!trimmed.isEmpty,
			let separator = trimmed.range(of: ": ")
		else {
			return nil
		}

		let reference = String(trimmed[trimmed.startIndex ..< separator.lowerBound])
		guard reference.hasPrefix("stash@{"), reference.hasSuffix("}") else {
			return nil
		}

		let subject = String(trimmed[separator.upperBound...])
		let (branch, message) = splitBranch(from: subject)
		return GitStashEntry(reference: reference, branch: branch, message: message)
	}

	/// Splits `WIP on <branch>: <rest>` / `On <branch>: <rest>` into its two halves.
	private static func splitBranch(from subject: String) -> (branch: String?, message: String) {
		let withoutPrefix: Substring
		if subject.hasPrefix("WIP on ") {
			withoutPrefix = subject.dropFirst("WIP on ".count)
		}
		else if subject.hasPrefix("On ") {
			withoutPrefix = subject.dropFirst("On ".count)
		}
		else {
			// `git stash store` accepts an arbitrary message with no branch in it.
			return (nil, subject)
		}

		guard let colon = withoutPrefix.firstIndex(of: ":") else {
			return (nil, subject)
		}

		let branch = String(withoutPrefix[withoutPrefix.startIndex ..< colon])
		let message = String(withoutPrefix[withoutPrefix.index(after: colon)...])
			.trimmingCharacters(in: .whitespaces)
		// A stash taken on a detached HEAD records the literal "(no branch)".
		return (branch == "(no branch)" || branch.isEmpty ? nil : branch, message)
	}
}
