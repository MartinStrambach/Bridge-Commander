import Foundation

// MARK: - Git Stash Entry

/// One entry of `git stash list`.
public struct GitStashEntry: Equatable, Sendable {
	/// The `stash@{n}` reference this entry can be applied or dropped by. Indices shift
	/// whenever an entry is added or removed, so a reference is only good for as long as
	/// the list it was parsed from — `GitStashHelper` looks the entry up again by `commit`
	/// right before acting on it.
	public let reference: String
	/// The stash commit, which unlike `reference` stays put while other entries come and go.
	/// Nil when the list was read without it (`git stash list`'s default format).
	public let commit: String?
	/// The branch the stash was taken on, or nil when git recorded no usable branch
	/// (a detached HEAD stashes as `(no branch)`).
	public let branch: String?
	/// Whatever follows the branch: the commit subject for a plain `git stash`, the
	/// custom text for `git stash push -m`.
	public let message: String

	public init(reference: String, commit: String? = nil, branch: String?, message: String) {
		self.reference = reference
		self.commit = commit
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

	/// The `git stash list` format `parse(_:)` reads the stash commit from: git's default
	/// (`%gd: %gs`) led by the commit, so an entry can be found again after its index shifted.
	public static let listFormat = "--format=%H %gd: %gs"

	/// Parses the output of `git stash list`, in its default format or in `listFormat`.
	///
	/// Every line is `[<commit> ]<reference>: <subject>`, where the subject is `WIP on <branch>: <sha> <text>`
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

	/// `entry` as it stands in a newer read of the list, under its current `stash@{n}`.
	///
	/// Matched by commit, so a stash pushed or dropped in another worktree since `entry` was
	/// read cannot make apply, pop or drop act on a different one. An entry read without its
	/// commit can only be matched where it was, and only if that slot still holds the same stash.
	/// - Returns: The entry, or nil when it is no longer in the list.
	public static func entry(matching entry: GitStashEntry, in entries: [GitStashEntry]) -> GitStashEntry? {
		guard let commit = entry.commit else {
			return entries.first {
				$0.reference == entry.reference && $0.branch == entry.branch && $0.message == entry.message
			}
		}

		return entries.first { $0.commit == commit }
	}

	// MARK: - Private

	private static func parseLine(_ line: String) -> GitStashEntry? {
		var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
		let commit = leadingCommit(of: trimmed)
		if let commit {
			trimmed = String(trimmed.dropFirst(commit.count + 1))
		}
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
		return GitStashEntry(reference: reference, commit: commit, branch: branch, message: message)
	}

	/// The object name `listFormat` puts before the reference: 40 hex digits, or 64 in a
	/// SHA-256 repository. A reference starts with `stash@{`, so the two cannot be confused.
	private static func leadingCommit(of line: String) -> String? {
		guard let space = line.firstIndex(of: " ") else {
			return nil
		}

		let candidate = line[line.startIndex ..< space]
		guard candidate.count == 40 || candidate.count == 64, candidate.allSatisfy(\.isHexDigit) else {
			return nil
		}

		return String(candidate)
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
