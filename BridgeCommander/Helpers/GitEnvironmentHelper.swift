import Foundation

nonisolated enum GitEnvironmentHelper {

	/// Sets up the environment for Git processes with enhanced PATH
	/// - Returns: Environment dictionary with common Git tool paths included
	static func setupEnvironment() -> [String: String] {
		var environment = ProcessInfo.processInfo.environment
		if let path = environment["PATH"] {
			environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
		}
		return environment
	}
}
