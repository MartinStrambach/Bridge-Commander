import Darwin

/// Reads the current working directory of a process.
///
/// Asked of a pane's shell, not of whatever runs in its foreground: the shell's directory is the
/// one a new shell has to start in to put the user back where they were, and a program the shell
/// launched (Claude Code, a build) may have changed its own directory without the shell moving.
///
/// Read from the kernel (`PROC_PIDVNODEPATHINFO`) rather than tracked through OSC 7: zsh reports
/// its directory that way only inside Terminal.app (`/etc/zshrc_Apple_Terminal`), so the escape
/// would arrive from some shells and not from others.
enum ProcessWorkingDirectory {
	/// The directory, or `nil` for a process that has exited or that this app may not inspect.
	static func of(processId pid: pid_t) -> String? {
		guard pid > 0 else {
			return nil
		}

		var info = proc_vnodepathinfo()
		let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
		guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
			return nil
		}

		let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
			String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
		}
		return path.isEmpty ? nil : path
	}
}
