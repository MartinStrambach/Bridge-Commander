import Foundation

public nonisolated enum EnvironmentHelper {

	/// Sets up the environment for processes with enhanced PATH
	/// - Returns: Environment dictionary with common tool paths included
	public static func setupEnvironment() -> [String: String] {
		var environment = ProcessInfo.processInfo.environment
		if let path = environment["PATH"] {
			environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
		}
		return environment
	}
}
