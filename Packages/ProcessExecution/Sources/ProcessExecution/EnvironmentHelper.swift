import Foundation

public nonisolated enum EnvironmentHelper {

	/// Built once. `ProcessInfo.processInfo.environment` allocates a fresh dictionary on every
	/// access, and this is read for every spawned process — several git invocations per
	/// repository row per refresh. The app's own environment is fixed at launch, so there is
	/// nothing to re-read.
	private static let cachedEnvironment: [String: String] = {
		var environment = ProcessInfo.processInfo.environment
		if let path = environment["PATH"] {
			environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
		}
		return environment
	}()

	/// Sets up the environment for processes with enhanced PATH
	/// - Returns: Environment dictionary with common tool paths included
	public static func setupEnvironment() -> [String: String] {
		cachedEnvironment
	}
}
