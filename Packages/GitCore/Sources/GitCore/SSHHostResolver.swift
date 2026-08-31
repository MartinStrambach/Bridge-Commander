import Foundation
import ProcessExecution

/// Resolves an SSH host alias (e.g. `gitlab-work` defined in ~/.ssh/config for a
/// multi-account setup) to the real hostname ssh would connect to.
public nonisolated enum SSHHostResolver {
	/// Runs `ssh -G <host>`, which evaluates the local ssh configuration without any
	/// network access, and returns the effective `hostname`. Falls back to the input
	/// host when resolution fails, so callers can use the result unconditionally.
	public static func resolveHostname(for host: String) async -> String {
		// A host beginning with "-" would be parsed by ssh as an option, not an operand.
		guard !host.isEmpty, !host.hasPrefix("-") else {
			return host
		}

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/ssh"),
			arguments: ["-G", host]
		)
		guard result.success else {
			return host
		}
		return hostname(fromSSHConfigDump: result.outputString) ?? host
	}

	/// Extracts the `hostname` entry from `ssh -G` output — one lowercase `key value`
	/// pair per line. Internal (not private) so the parsing is unit-testable.
	static func hostname(fromSSHConfigDump output: String) -> String? {
		for line in output.split(separator: "\n") where line.hasPrefix("hostname ") {
			let value = line.dropFirst("hostname ".count).trimmingCharacters(in: .whitespaces)
			return value.isEmpty ? nil : value
		}
		return nil
	}
}
