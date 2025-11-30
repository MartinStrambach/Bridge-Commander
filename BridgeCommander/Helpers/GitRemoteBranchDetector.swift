import Foundation

enum GitRemoteBranchDetector {
	/// Checks if the current branch has a remote tracking branch
	static func hasRemoteBranch(at path: String) async -> Bool {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.currentDirectoryPath = path
			process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
			process.arguments = ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]

			let pipe = Pipe()
			process.standardOutput = pipe
			process.standardError = Pipe()

			process.terminationHandler = { process in
				// If exit status is 0, remote branch exists
				if process.terminationStatus == 0 {
					let data = pipe.fileHandleForReading.readDataToEndOfFile()
					let output = String(data: data, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					continuation.resume(returning: !output.isEmpty)
				}
				else {
					continuation.resume(returning: false)
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(returning: false)
			}
		}
	}
}
