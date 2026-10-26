import Darwin
import Dispatch

/// Waits for a hung-up shell to exit and collects its exit status, so it does not linger as a
/// zombie.
///
/// SwiftTerm reaps a pane's shell from an exit monitor its `LocalProcess` owns — the only place it
/// calls `waitpid` — and cancels that monitor when the process object is released. A killed pane is
/// released straight after its shell is sent SIGHUP, before the shell has had time to exit, so
/// nothing was left to wait for it: every closed tab and deleted worktree left a `(zsh)` zombie
/// until the app quit.
enum ShellReaper {
	/// Serial, so the exit event, the retries after it and the check made when a monitor is armed
	/// never race: a pid that has been waited for once may already belong to a new child of this
	/// process.
	private static let queue = DispatchQueue(label: "com.bridgecommander.terminal.shell-reaper")

	/// The exit monitors still waiting, by pid. A source that nobody holds is released and never
	/// fires, so each is kept here until its shell has been reaped. Only touched on `queue`.
	private nonisolated(unsafe) static var monitors: [pid_t: any DispatchSourceProcess] = [:]

	/// Reaps `pid`, a child of this process, once it exits. Call it only for a child nothing else
	/// will wait for.
	static func reap(_ pid: pid_t) {
		guard pid > 0 else {
			return
		}

		queue.async {
			guard monitors[pid] == nil else {
				return
			}

			let monitor = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
			monitor.setEventHandler {
				collectAfterExit(pid)
			}
			monitors[pid] = monitor
			monitor.activate()
			// A shell that exited before the monitor was armed may never deliver it an exit event.
			collect(pid)
		}
	}

	/// The exit event comes a moment before the process can be waited for — `waitpid` right after
	/// it often still finds it running — and it comes once, so the wait is retried until it lands.
	private static func collectAfterExit(_ pid: pid_t) {
		guard !collect(pid) else {
			return
		}

		queue.asyncAfter(deadline: .now() + .milliseconds(10)) {
			collectAfterExit(pid)
		}
	}

	/// Collects `pid`'s exit status if it has exited, and stops watching it. `ECHILD` also ends the
	/// watch: SwiftTerm got there first, which it can when the pane outlives its shell.
	///
	/// - Returns: Whether `pid` is no longer watched.
	@discardableResult
	private static func collect(_ pid: pid_t) -> Bool {
		guard let monitor = monitors[pid] else {
			return true
		}

		var status: Int32 = 0
		guard waitpid(pid, &status, WNOHANG) != 0 else {
			return false // still running
		}

		monitor.cancel()
		monitors[pid] = nil
		return true
	}
}
