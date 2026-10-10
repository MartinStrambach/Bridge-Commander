import ComposableArchitecture
@testable import RepositoryFeature

extension TestStore where State == RepositoryListReducer.State {
	/// Marks repositories as added: a scan builds a group only for a tracked one, so a scan landing
	/// after its group was removed does not bring it back.
	func track(_ paths: String...) {
		state.$trackedRepoPaths.withLock { $0 = paths }
	}
}
