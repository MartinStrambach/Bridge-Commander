import AppIntents
import CoreSpotlight
import Foundation
import OSLog

/// Keeps Spotlight's copy of the tracked repositories in step with the sidebar.
enum RepositoryIndexer {
	private static let logger = Logger(subsystem: "com.bridgecommander.BridgeCommander", category: "RepositoryIndexer")

	/// Replaces every indexed repository with `paths`. Delete-then-add rather than a diff:
	/// the index is not readable back, and a removed repository must stop being offered to
	/// Siri, so the only reliable state is "exactly what is tracked now". A handful of items,
	/// so rebuilding costs nothing.
	static func reindex(paths: [String]) async throws {
		let index = CSSearchableIndex.default()
		try await index.deleteAppEntities(ofType: RepositoryEntity.self)
		guard !paths.isEmpty else {
			return
		}
		try await index.indexAppEntities(paths.map(RepositoryEntity.init(id:)))
	}

	/// For callers that should not fail over a Spotlight hiccup: the intents still work
	/// without the index, Siri just knows the names less well.
	static func reindexLoggingFailure(paths: [String]) async {
		do {
			try await reindex(paths: paths)
		}
		catch {
			logger.error("Indexing repositories failed: \(error.localizedDescription, privacy: .public)")
		}
	}
}
