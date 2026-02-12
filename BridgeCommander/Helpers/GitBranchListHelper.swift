import Foundation

struct BranchInfo: Equatable, Hashable {
	let name: String
	let existsLocally: Bool
	let existsRemotely: Bool

	var isRemoteOnly: Bool {
		existsRemotely && !existsLocally
	}
}

enum GitBranchListHelper {

	/// Lists all local and remote branches in the repository with their location info
	/// - Parameter repositoryPath: The path to the Git repository
	/// - Returns: Array of BranchInfo objects
	static func listBranchesWithInfo(at repositoryPath: String) async -> [BranchInfo] {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(fileURLWithPath: repositoryPath)
			process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
			process.arguments = [
				"for-each-ref",
				"--format=%(refname:short)",
				"refs/heads/",
				"refs/remotes/origin/"
			]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			let outputCollector = PipeDataCollector()
			let errorCollector = PipeDataCollector()

			// Continuously read from output pipe in background to prevent buffer overflow
			outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
				let data = fileHandle.availableData
				outputCollector.append(data)
			}

			// Continuously read from error pipe in background to prevent buffer overflow
			errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
				let data = fileHandle.availableData
				errorCollector.append(data)
			}

			process.terminationHandler = { _ in
				// Stop reading from pipes
				outputPipe.fileHandleForReading.readabilityHandler = nil
				errorPipe.fileHandleForReading.readabilityHandler = nil

				// Read any remaining data
				let remainingOutput = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
				let remainingError = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()

				// Combine all output
				outputCollector.append(remainingOutput)
				errorCollector.append(remainingError)

				let data = outputCollector.getData()
				if let output = String(data: data, encoding: .utf8) {
					let allBranches = output
						.split(separator: "\n")
						.map { String($0) }
						.filter { $0 != "origin/HEAD" }

					// Separate local and remote branches
					var localBranches = Set<String>()
					var remoteBranches = Set<String>()

					for branch in allBranches {
						if branch.hasPrefix("origin/") {
							let name = branch.replacingOccurrences(of: "origin/", with: "")
							remoteBranches.insert(name)
						}
						else {
							localBranches.insert(branch)
						}
					}

					// Combine into BranchInfo objects
					let allBranchNames = localBranches.union(remoteBranches)
					let branchInfos = allBranchNames.map { name in
						BranchInfo(
							name: name,
							existsLocally: localBranches.contains(name),
							existsRemotely: remoteBranches.contains(name)
						)
					}
					.sorted { $0.name < $1.name }

					continuation.resume(returning: branchInfos)
				}
				else {
					continuation.resume(returning: [])
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(returning: [])
			}
		}
	}
}
