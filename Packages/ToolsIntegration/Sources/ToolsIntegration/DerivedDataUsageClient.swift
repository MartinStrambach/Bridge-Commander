import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct DerivedDataUsageClient: Sendable {
	/// Measures Xcode's DerivedData folder; see `DerivedDataUsageScanner.measure`.
	public var measure: @Sendable () -> AsyncStream<DerivedDataUsage> = { .finished }
	/// Deletes the folders of an orphaned or leftover kind; see `DerivedDataUsageScanner.deleteFolders`.
	public var deleteFolders: @Sendable (_ of: DerivedDataUsage.Kind) async -> DerivedDataDeletion = { _ in DerivedDataDeletion() }
}

extension DerivedDataUsageClient: DependencyKey {
	public static let liveValue = DerivedDataUsageClient(
		measure: { DerivedDataUsageScanner.measure() },
		deleteFolders: { kind in DerivedDataUsageScanner.deleteFolders(of: kind) }
	)
}

extension DerivedDataUsageClient: TestDependencyKey {
	public static let testValue = DerivedDataUsageClient()
}
