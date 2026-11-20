import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Dependency Graph Client

/// Reads a repository's module graph from its build files, and which modules its branch changed.
@DependencyClient
public struct DependencyGraphClient: Sendable {
	public var loadGraph: @Sendable (_ repositoryPath: String, _ iosSubfolderPath: String) async throws -> DependencyGraph
	public var loadChanges: @Sendable (
		_ repositoryPath: String,
		_ configuredDefaultBranch: String,
		_ modules: [DependencyModule]
	) async throws -> ModuleChanges
}

// MARK: - Live Implementation

extension DependencyGraphClient: DependencyKey {
	public static var liveValue: DependencyGraphClient {
		DependencyGraphClient(
			loadGraph: { repositoryPath, iosSubfolderPath in
				// A few hundred file reads: off the cooperative pool, which must not wait on disk.
				await withCheckedContinuation { continuation in
					loaderQueue.async {
						continuation.resume(returning: DependencyGraphLoader.load(
							iosSubfolderPath: iosSubfolderPath,
							fileSystem: .live(repositoryPath: repositoryPath)
						))
					}
				}
			},
			loadChanges: { repositoryPath, configuredDefaultBranch, modules in
				let changes = try await GitBranchChangesHelper.changes(
					at: repositoryPath,
					configuredDefaultBranch: configuredDefaultBranch
				)
				let existing = try await GitBranchChangesHelper.existingFolders(
					ModuleChangeClassifier.directories(of: modules),
					at: changes.mergeBase,
					in: repositoryPath
				)
				let classified = ModuleChangeClassifier.classify(
					changedPaths: changes.changedPaths,
					modules: modules,
					existingDirectoriesAtBase: existing
				)
				return ModuleChanges(
					baseRef: changes.baseRef,
					mergeBase: changes.mergeBase,
					newModules: classified.new,
					changedModules: classified.changed,
					changedFileCounts: classified.counts
				)
			}
		)
	}

	private static let loaderQueue = DispatchQueue(label: "DependencyGraphClient.loader", qos: .userInitiated)
}

extension DependencyGraphClient: TestDependencyKey {
	public static var testValue: DependencyGraphClient { DependencyGraphClient() }
}
