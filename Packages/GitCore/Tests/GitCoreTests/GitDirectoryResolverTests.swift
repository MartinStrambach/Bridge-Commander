import Testing
@testable import GitCore

@Suite("GitDirectoryResolver")
struct GitDirectoryResolverTests {
	// MARK: - commonGitDirectory

	@Test("worktree git dir maps to the main repository's .git directory")
	func worktreeMapsToCommonDir() {
		#expect(
			GitDirectoryResolver.commonGitDirectory(from: "/repos/app/.git/worktrees/feature-x")
				== "/repos/app/.git"
		)
	}

	@Test("regular repository .git directory is returned unchanged")
	func regularRepoUnchanged() {
		#expect(GitDirectoryResolver.commonGitDirectory(from: "/repos/app/.git") == "/repos/app/.git")
	}

	@Test("submodule git dir is returned unchanged")
	func submoduleUnchanged() {
		#expect(
			GitDirectoryResolver.commonGitDirectory(from: "/repos/app/.git/modules/sub")
				== "/repos/app/.git/modules/sub"
		)
	}

	@Test("only a trailing worktrees component is stripped")
	func directoryNamedWorktreesNotStripped() {
		// A parent folder literally named "worktrees" must not trigger stripping.
		#expect(
			GitDirectoryResolver.commonGitDirectory(from: "/Users/me/worktrees/app/.git")
				== "/Users/me/worktrees/app/.git"
		)
		// ...but a worktree of a repo living under such a folder still maps correctly.
		#expect(
			GitDirectoryResolver.commonGitDirectory(from: "/Users/me/worktrees/app/.git/worktrees/opt")
				== "/Users/me/worktrees/app/.git"
		)
	}

	@Test("path too short to contain a worktrees segment is returned unchanged")
	func shortPathUnchanged() {
		#expect(GitDirectoryResolver.commonGitDirectory(from: "/.git") == "/.git")
	}
}
