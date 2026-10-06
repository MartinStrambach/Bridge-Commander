import Foundation

/// Normalizes user-typed branch names into something git will accept as a ref name.
///
/// Git rejects whitespace anywhere in a ref name, so a name typed as
/// "fix login bug" would make `git worktree add -b` fail. Every whitespace
/// character (space, tab, newline — the latter two can arrive via paste) becomes
/// an underscore, matching the convention `BranchNameFormatter` reverses for display.
///
/// Leading whitespace is dropped instead: it is never meant as part of a name, and turning it into
/// underscores made a name typed as only spaces a submittable "___". Trailing whitespace still
/// becomes an underscore, since this runs on every keystroke and a trailing space is usually the
/// gap before the next word.
public nonisolated enum GitBranchNameSanitizer {
	public static func sanitize(_ name: String) -> String {
		String(name.drop(while: \.isWhitespace).map { $0.isWhitespace ? "_" : $0 })
	}
}
