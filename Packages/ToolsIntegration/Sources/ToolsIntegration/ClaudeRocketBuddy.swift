import ActivityLog
import CryptoKit
import Dependencies
import DependenciesMacros
import Foundation
import ProcessExecution

/// The rocket-buddy Claude Code mod (Settings ▸ Terminal ▸ Claude Code): a rocket and its
/// astronaut crew in the band above Claude's prompt, acting out what Claude is doing.
///
/// Downloaded on demand from a Bridge Commander release, pinned by URL and SHA-256, into
/// Application Support. A built-in terminal's shell is pointed at that copy through
/// `CLAUDE_CODE_PLUGIN_DIRS`, which Claude Code loads like `--plugin-dir`.
public nonisolated enum ClaudeRocketBuddy {
	struct Release {
		let version: String
		let url: URL
		let sha256: String
	}

	/// Printed by `scripts/package-rocket-buddy.sh`.
	static let release = Release(
		version: "0.1.0",
		url: URL(string: "https://github.com/MartinStrambach/Bridge-Commander/releases/download/rocket-buddy-0.1.0/rocket-buddy-0.1.0.zip")!,
		sha256: "b97169a58df873aa4922f97a3b01d8d4ea2ea0d956abe0d1424bd6c3e478ce61"
	)

	/// Where the pinned zip is fetched from. A Debug build reads the `rocketBuddyDownloadURL`
	/// default first, so the download can be tried before its release exists, from a local server
	/// or a `file://` URL of the zip `scripts/package-rocket-buddy.sh` writes. The SHA-256 is
	/// checked all the same.
	static var downloadURL: URL {
		#if DEBUG
			if let override = UserDefaults.standard.string(forKey: "rocketBuddyDownloadURL"), let url = URL(string: override) {
				return url
			}
		#endif
		return release.url
	}

	enum InstallError: LocalizedError {
		case download(statusCode: Int)
		case checksumMismatch
		case unzip(String)
		case notAPlugin

		var errorDescription: String? {
			switch self {
			case let .download(statusCode):
				"The download failed (HTTP \(statusCode))."
			case .checksumMismatch:
				"The download is not the expected file."
			case let .unzip(message):
				"The download could not be unpacked: \(message)"
			case .notAPlugin:
				"The download holds no Claude Code plugin."
			}
		}
	}

	/// The variables that make a `claude` started in a pane load the mod and draw it in 3D. Empty
	/// until the mod is downloaded; a missing copy is then downloaded in the background, for the
	/// shells started after it arrives.
	public static func environment() -> [String] {
		if let folder = installedFolder(in: installRoot, version: release.version) {
			return variables(pluginFolder: folder)
		}
		Task {
			try? await ensureInstalled()
		}
		return []
	}

	/// `CLAUDE_CODE_FORCE_TERMINAL_IMAGES` makes Claude Code send pictures to SwiftTerm, which
	/// draws Kitty graphics but does not identify as a terminal Claude Code knows to have them;
	/// the mod then picks its 3D frames too.
	static func variables(pluginFolder: URL) -> [String] {
		["CLAUDE_CODE_PLUGIN_DIRS=\(pluginFolder.path(percentEncoded: false))", "CLAUDE_CODE_FORCE_TERMINAL_IMAGES=1"]
	}

	/// Named after the bundle identifier, so a Debug build keeps a copy of its own.
	static var installRoot: URL {
		URL.applicationSupportDirectory
			.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
			.appending(path: "ClaudePlugins/rocket-buddy", directoryHint: .isDirectory)
	}

	/// `root/<version>/rocket-buddy`, when that version is installed.
	static func installedFolder(in root: URL, version: String) -> URL? {
		let folder = root.appending(path: "\(version)/rocket-buddy", directoryHint: .isDirectory)
		return FileManager.default.fileExists(atPath: manifest(in: folder).path(percentEncoded: false)) ? folder : nil
	}

	/// Downloads and installs the pinned release unless it is installed already. Concurrent
	/// calls share one download.
	static func ensureInstalled() async throws {
		try await downloads.run {
			guard installedFolder(in: installRoot, version: release.version) == nil else {
				return
			}
			try await ActivityLog.shared.recordingErrors("Downloading the rocket buddy") {
				let url = downloadURL
				let (data, response) = try await URLSession.shared.loggedData(for: URLRequest(url: url))
				// A file URL, which only a Debug build's override names, has no status code.
				if let statusCode = (response as? HTTPURLResponse)?.statusCode ?? (url.isFileURL ? nil : -1),
				   statusCode != 200
				{
					throw InstallError.download(statusCode: statusCode)
				}
				_ = try await install(archive: data, sha256: release.sha256, version: release.version, into: installRoot)
			}
		}
	}

	private static let downloads = Downloads()

	private actor Downloads {
		private var current: Task<Void, any Error>?

		func run(_ operation: @escaping @Sendable () async throws -> Void) async throws {
			if let current {
				return try await current.value
			}
			let task = Task(operation: operation)
			current = task
			defer { current = nil }
			try await task.value
		}
	}

	/// Checks `archive` against `sha256`, unpacks it to `root/<version>/rocket-buddy` and removes
	/// every other version. The archive holds one `rocket-buddy` folder. Staged beside the
	/// target and moved in whole, so an interrupted install never passes for one.
	static func install(archive: Data, sha256: String, version: String, into root: URL) async throws -> URL {
		let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
		guard digest == sha256 else {
			throw InstallError.checksumMismatch
		}

		let fileManager = FileManager.default
		let staging = root.appending(component: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
		try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: staging) }

		let zip = staging.appending(component: "download.zip")
		try archive.write(to: zip)
		let unpacked = staging.appending(component: "unpacked", directoryHint: .isDirectory)
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/ditto"),
			arguments: ["-x", "-k", zip.path(percentEncoded: false), unpacked.path(percentEncoded: false)]
		)
		guard result.success else {
			throw InstallError.unzip(result.trimmedError)
		}
		let plugin = unpacked.appending(component: "rocket-buddy", directoryHint: .isDirectory)
		guard fileManager.fileExists(atPath: manifest(in: plugin).path(percentEncoded: false)) else {
			throw InstallError.notAPlugin
		}

		let versionFolder = root.appending(component: version, directoryHint: .isDirectory)
		try? fileManager.removeItem(at: versionFolder)
		try fileManager.createDirectory(at: versionFolder, withIntermediateDirectories: true)
		let installed = versionFolder.appending(component: "rocket-buddy", directoryHint: .isDirectory)
		try fileManager.moveItem(at: plugin, to: installed)

		// Earlier versions, and staging folders an interrupted install left behind.
		for item in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
			where item.lastPathComponent != version && item.lastPathComponent != staging.lastPathComponent
		{
			try? fileManager.removeItem(at: item)
		}
		return installed
	}

	private static func manifest(in plugin: URL) -> URL {
		plugin.appending(path: ".claude-plugin/plugin.json")
	}
}

// MARK: - Client

/// What Settings needs: whether the mod is downloaded, and downloading it.
@DependencyClient
public struct ClaudeRocketBuddyClient: Sendable {
	public var isInstalled: @Sendable () -> Bool = { false }
	public var install: @Sendable () async throws -> Void
}

extension ClaudeRocketBuddyClient: DependencyKey {
	public static let liveValue = ClaudeRocketBuddyClient(
		isInstalled: {
			ClaudeRocketBuddy.installedFolder(
				in: ClaudeRocketBuddy.installRoot,
				version: ClaudeRocketBuddy.release.version
			) != nil
		},
		install: {
			try await ClaudeRocketBuddy.ensureInstalled()
		}
	)
}

extension ClaudeRocketBuddyClient: TestDependencyKey {
	public static let testValue = ClaudeRocketBuddyClient()
}
