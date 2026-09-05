import Foundation

/// Normalizes user-typed branch names into something git will accept as a ref name.
///
/// Git rejects whitespace anywhere in a ref name, so a name typed as
/// "fix login bug" would make `git worktree add -b` fail. Every whitespace
/// character (space, tab, newline — the latter two can arrive via paste) becomes
/// an underscore, matching the convention `BranchNameFormatter` reverses for display.
public nonisolated enum GitBranchNameSanitizer {
	public static func sanitize(_ name: String) -> String {
		String(name.map { $0.isWhitespace ? "_" : $0 })
	}
}
