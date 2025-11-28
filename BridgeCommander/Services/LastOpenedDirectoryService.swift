import Foundation

final class LastOpenedDirectoryServiceImpl: LastOpenedDirectoryServiceType {
	private let userDefaults: UserDefaults
	private let key = "lastOpenedDirectory"

	init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
	}

	func load() -> String? {
		userDefaults.string(forKey: key)
	}

	func save(_ directory: String) {
		userDefaults.set(directory, forKey: key)
	}

	func clear() {
		userDefaults.removeObject(forKey: key)
	}
}
