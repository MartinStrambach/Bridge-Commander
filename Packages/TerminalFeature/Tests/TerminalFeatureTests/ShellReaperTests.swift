import Darwin
import Foundation
import Testing

@testable import TerminalFeature

/// Starts `path` as a direct child of this process. Not `Process`, which reaps its children itself.
private func spawn(_ path: String, _ arguments: [String] = []) -> pid_t {
	var pid: pid_t = 0
	let argv = ([path] + arguments).map { strdup($0) } + [nil]
	defer {
		argv.forEach { free($0) }
	}
	return posix_spawn(&pid, path, nil, nil, argv, nil) == 0 ? pid : 0
}

/// Whether a process exists, a zombie included. Does not reap it.
private func exists(_ pid: pid_t) -> Bool {
	kill(pid, 0) == 0
}

private func eventually(within timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
	let clock = ContinuousClock()
	let deadline = clock.now + timeout
	while clock.now < deadline {
		if condition() {
			return true
		}

		try? await Task.sleep(for: .milliseconds(50))
	}
	return condition()
}

@Suite struct ShellReaperTests {
	@Test func reapsAChildWhenItExits() async throws {
		let pid = spawn("/bin/sleep", ["0.3"])
		try #require(pid > 0)

		ShellReaper.reap(pid)

		#expect(await eventually { !exists(pid) }, "the child should not be left a zombie")
	}

	/// The exit can come before the monitor is armed — a shell that dies the moment it is hung up —
	/// and a monitor armed on a zombie may never hear of it.
	@Test func reapsAChildThatHasAlreadyExited() async throws {
		let pid = spawn("/usr/bin/true")
		try #require(pid > 0)
		try await Task.sleep(for: .milliseconds(300))
		try #require(exists(pid), "the child should be a zombie until reaped")

		ShellReaper.reap(pid)

		#expect(await eventually { !exists(pid) }, "the child should not be left a zombie")
	}
}
