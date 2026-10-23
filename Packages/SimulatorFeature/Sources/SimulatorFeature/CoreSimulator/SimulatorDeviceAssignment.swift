import Foundation

/// Which simulator a repository's (worktree's) terminal and pane use when a call names none.
/// Each repository keeps its own device; one without a booted device of its own takes a booted
/// device no other repository has chosen, never another worktree's — two `claude`s driving one
/// simulator undo each other's taps. Choosing another repository's device in the pane, or naming
/// it with `udid`, still shares it on purpose. Pure, so it is tested; `SimulatorHost` reads the
/// choices from `UserDefaults`.
struct SimulatorDeviceAssignment: Equatable, Sendable {
	/// The result of `resolve`.
	enum Resolution: Equatable, Sendable {
		case device(String)
		case noBootedDevice
		/// Every booted device is another repository's, by device: the repositories that chose it.
		case everyBootedDeviceTaken([String: [String]])
	}

	/// Each repository's device, by repository path.
	var selections: [String: String]
	/// The device chosen last, anywhere.
	var lastSelected: String?

	/// The devices repositories other than `repositoryPath` have chosen, each with the
	/// repositories that chose it (sorted). For `nil` — a `claude` outside the app — that is
	/// every repository's.
	func devicesOfOtherRepositories(than repositoryPath: String?) -> [String: [String]] {
		var devices: [String: [String]] = [:]
		for (path, deviceId) in selections where path != repositoryPath {
			devices[deviceId, default: []].append(path)
		}
		return devices.mapValues { $0.sorted() }
	}

	/// The device `repositoryPath`'s pane shows and `list_devices` marks: its own choice, else the
	/// last one made anywhere unless another repository has it. `nil` gets the last one.
	func storedDeviceId(repositoryPath: String?) -> String? {
		guard let repositoryPath else {
			return lastSelected
		}
		if let own = selections[repositoryPath] {
			return own
		}
		guard let lastSelected, devicesOfOtherRepositories(than: repositoryPath)[lastSelected] == nil else {
			return nil
		}
		return lastSelected
	}

	/// The device a tool call without a `udid` acts on, among `bootedIds` (in device-list order):
	/// the repository's own if booted, else a booted one no other repository has chosen — the
	/// last one chosen anywhere if it is free. A `claude` outside the app owns no device, so it
	/// falls back to any booted one rather than failing.
	func resolve(bootedIds: [String], repositoryPath: String?) -> Resolution {
		if let own = storedDeviceId(repositoryPath: repositoryPath), bootedIds.contains(own) {
			return .device(own)
		}
		let taken = devicesOfOtherRepositories(than: repositoryPath)
		let free = bootedIds.filter { taken[$0] == nil }
		if let lastSelected, free.contains(lastSelected) {
			return .device(lastSelected)
		}
		if let first = free.first {
			return .device(first)
		}
		guard let anyBooted = bootedIds.first else {
			return .noBootedDevice
		}
		guard repositoryPath != nil else {
			return .device(anyBooted)
		}
		return .everyBootedDeviceTaken(taken.filter { bootedIds.contains($0.key) })
	}
}
