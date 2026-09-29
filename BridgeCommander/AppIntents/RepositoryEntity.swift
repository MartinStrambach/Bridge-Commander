import AppIntents
import ComposableArchitecture
import CoreSpotlight
import Foundation
import Settings

/// A tracked repository as Siri, Shortcuts and Spotlight see it. The id is the tracked root
/// path — the same string the repository list uses as its group id.
///
/// Indexed in Spotlight (`RepositoryIndexer`) so Siri knows the repository names before it is
/// asked, instead of only finding them by querying the app mid-request.
struct RepositoryEntity: IndexedEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Repository")
	static let defaultQuery = RepositoryEntityQuery()

	let id: String

	var name: String {
		URL(fileURLWithPath: id).lastPathComponent
	}

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
	}

	var attributeSet: CSSearchableItemAttributeSet {
		let attributes = defaultAttributeSet
		attributes.title = name
		attributes.displayName = name
		attributes.contentDescription = "Git repository at \(id)"
		// Spoken names rarely keep the separators: "bridge commander" for Bridge-Commander.
		let spoken = name.replacingOccurrences(of: "[-_.]", with: " ", options: .regularExpression)
		attributes.keywords = Array(Set([name, spoken, "repository", "repo", "git"]))
		return attributes
	}
}

struct RepositoryEntityQuery: EntityStringQuery {
	func entities(for identifiers: [String]) async throws -> [RepositoryEntity] {
		let tracked = Set(Self.trackedPaths())
		return identifiers.filter(tracked.contains).map(RepositoryEntity.init(id:))
	}

	func entities(matching string: String) async throws -> [RepositoryEntity] {
		let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
		return try await suggestedEntities().filter {
			$0.name.localizedCaseInsensitiveContains(query)
		}
	}

	func suggestedEntities() async throws -> [RepositoryEntity] {
		Self.trackedPaths().map(RepositoryEntity.init(id:))
	}

	/// Read from the list's own file storage, so an intent sees exactly the repositories the
	/// sidebar shows, in the same order.
	static func trackedPaths() -> [String] {
		@SharedReader(.trackedRepoPaths) var paths: [String] = []
		return paths
	}
}

@available(macOS 27.0, *)
extension RepositoryEntityQuery: IndexedEntityQuery {
	/// Called by the system when it wants the index rebuilt (e.g. after it was dropped).
	func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
		try await RepositoryIndexer.reindex(paths: Self.trackedPaths())
	}

	func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
		let tracked = Set(Self.trackedPaths())
		let (present, gone) = (identifiers.filter(tracked.contains), identifiers.filter { !tracked.contains($0) })
		let index = CSSearchableIndex.default()
		if !gone.isEmpty {
			try await index.deleteAppEntities(identifiedBy: gone, ofType: RepositoryEntity.self)
		}
		if !present.isEmpty {
			try await index.indexAppEntities(present.map(RepositoryEntity.init(id:)))
		}
	}
}
