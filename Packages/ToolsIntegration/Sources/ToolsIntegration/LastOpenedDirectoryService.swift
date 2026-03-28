import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct LastOpenedDirectoryClient: @unchecked Sendable {
	public var load: () -> String? = { nil }
	public var save: (_ directory: String) -> Void
	public var clear: () -> Void
}

extension LastOpenedDirectoryClient: DependencyKey {
	public static let liveValue: LastOpenedDirectoryClient = {
		let userDefaults = UserDefaults.standard
		let key = "lastOpenedDirectory"

		return LastOpenedDirectoryClient(
			load: {
				userDefaults.string(forKey: key)
			},
			save: { directory in
				userDefaults.set(directory, forKey: key)
			},
			clear: {
				userDefaults.removeObject(forKey: key)
			}
		)
	}()
}

extension LastOpenedDirectoryClient: TestDependencyKey {
	public static let testValue = LastOpenedDirectoryClient()
}
