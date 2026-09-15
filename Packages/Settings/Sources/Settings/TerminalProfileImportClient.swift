import Dependencies
import DependenciesMacros
import Foundation

/// Imports Terminal.app color profiles, either from Terminal's own settings or from files the
/// user picked. Wrapped as a dependency so the reducer's import flow is testable without
/// touching the real Terminal.app preferences.
@DependencyClient
public struct TerminalProfileImportClient: Sendable {
	/// Every profile currently configured in Terminal.app.
	public var importFromTerminalApp: @Sendable () throws -> [TerminalProfile]
	/// The profile(s) in one exported `.terminal` file.
	public var importFromFile: @Sendable (_ url: URL) throws -> [TerminalProfile]
}

extension TerminalProfileImportClient: DependencyKey {
	public static let liveValue = TerminalProfileImportClient(
		importFromTerminalApp: { try TerminalProfileImporter.profilesFromTerminalApp() },
		importFromFile: { try TerminalProfileImporter.profiles(fromFileAt: $0) }
	)
}

extension TerminalProfileImportClient: TestDependencyKey {
	public static let testValue = TerminalProfileImportClient()
}
