import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct LastOpenedDirectoryClient: Sendable {
	var load: () -> String? = { nil }
	var save: (_ directory: String) -> Void
	var clear: () -> Void
}

extension LastOpenedDirectoryClient: DependencyKey {
	static let liveValue: LastOpenedDirectoryClient = {
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
	static let testValue = LastOpenedDirectoryClient()
}
