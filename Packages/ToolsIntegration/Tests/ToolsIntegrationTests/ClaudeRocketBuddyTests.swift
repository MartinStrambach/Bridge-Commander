import CryptoKit
import Foundation
import Testing

@testable import ToolsIntegration

@Suite("Claude rocket buddy")
struct ClaudeRocketBuddyTests {
	private let fileManager = FileManager.default

	@Test("installs a checked archive under its version, hidden manifest included")
	func installs() async throws {
		let temp = try temporaryFolder()
		defer { try? fileManager.removeItem(at: temp) }
		let archive = try makeArchive(in: temp, hook: "one")
		let root = temp.appending(component: "installed")

		let installed = try await ClaudeRocketBuddy.install(archive: archive, sha256: sha256(archive), version: "1.0.0", into: root)

		#expect(installed == root.appending(path: "1.0.0/rocket-buddy", directoryHint: .isDirectory))
		#expect(ClaudeRocketBuddy.installedFolder(in: root, version: "1.0.0") == installed)
		#expect(try hook(in: installed) == "one")
		#expect(try fileManager.contentsOfDirectory(atPath: root.path(percentEncoded: false)) == ["1.0.0"])
	}

	@Test("a new version replaces the old one and anything left behind")
	func newVersionReplacesOld() async throws {
		let temp = try temporaryFolder()
		defer { try? fileManager.removeItem(at: temp) }
		let root = temp.appending(component: "installed")
		let first = try makeArchive(in: temp, hook: "one")
		_ = try await ClaudeRocketBuddy.install(archive: first, sha256: sha256(first), version: "1.0.0", into: root)
		try fileManager.createDirectory(at: root.appending(component: ".staging-left-behind"), withIntermediateDirectories: true)

		let second = try makeArchive(in: temp, hook: "two")
		let installed = try await ClaudeRocketBuddy.install(archive: second, sha256: sha256(second), version: "1.1.0", into: root)

		#expect(try hook(in: installed) == "two")
		#expect(ClaudeRocketBuddy.installedFolder(in: root, version: "1.0.0") == nil)
		#expect(try fileManager.contentsOfDirectory(atPath: root.path(percentEncoded: false)) == ["1.1.0"])
	}

	@Test("an archive that is not the pinned one installs nothing")
	func rejectsWrongChecksum() async throws {
		let temp = try temporaryFolder()
		defer { try? fileManager.removeItem(at: temp) }
		let archive = try makeArchive(in: temp, hook: "one")
		let root = temp.appending(component: "installed")

		await #expect(throws: ClaudeRocketBuddy.InstallError.self) {
			try await ClaudeRocketBuddy.install(archive: archive, sha256: String(repeating: "0", count: 64), version: "1.0.0", into: root)
		}
		#expect(ClaudeRocketBuddy.installedFolder(in: root, version: "1.0.0") == nil)
	}

	@Test("an archive without a plugin installs nothing")
	func rejectsArchiveWithoutPlugin() async throws {
		let temp = try temporaryFolder()
		defer { try? fileManager.removeItem(at: temp) }
		let archive = try makeArchive(in: temp, hook: "one", manifest: false)
		let root = temp.appending(component: "installed")

		await #expect(throws: ClaudeRocketBuddy.InstallError.self) {
			try await ClaudeRocketBuddy.install(archive: archive, sha256: sha256(archive), version: "1.0.0", into: root)
		}
		#expect(ClaudeRocketBuddy.installedFolder(in: root, version: "1.0.0") == nil)
	}

	@Test("the pinned release is a rocket-buddy zip on a Bridge Commander release")
	func pinnedRelease() {
		let release = ClaudeRocketBuddy.release

		#expect(release.url.absoluteString.hasPrefix("https://github.com/MartinStrambach/Bridge-Commander/releases/download/"))
		#expect(release.url.lastPathComponent == "rocket-buddy-\(release.version).zip")
		#expect(release.sha256.count == 64)
	}

	@Test("the shell is pointed at the installed folder and told to draw pictures")
	func variables() {
		let folder = URL(filePath: "/Users/me/Library/Application Support/x/1.0.0/rocket-buddy", directoryHint: .isDirectory)

		#expect(ClaudeRocketBuddy.variables(pluginFolder: folder) == [
			"CLAUDE_CODE_PLUGIN_DIRS=/Users/me/Library/Application Support/x/1.0.0/rocket-buddy/",
			"CLAUDE_CODE_FORCE_TERMINAL_IMAGES=1",
		])
	}

	// MARK: - Helpers

	private func temporaryFolder() throws -> URL {
		let url = fileManager.temporaryDirectory.appending(component: "ClaudeRocketBuddyTests-\(UUID().uuidString)")
		try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	/// A zip holding one `rocket-buddy` folder, made the way `scripts/package-rocket-buddy.sh` does.
	private func makeArchive(in folder: URL, hook: String, manifest: Bool = true) throws -> Data {
		let source = folder.appending(path: "source-\(UUID().uuidString)", directoryHint: .isDirectory)
		let plugin = source.appending(component: "rocket-buddy", directoryHint: .isDirectory)
		if manifest {
			try write(#"{ "name": "rocket-buddy", "version": "1.0.0" }"#, to: plugin.appending(path: ".claude-plugin/plugin.json"))
		}
		try write(hook, to: plugin.appending(path: "hooks/register.tsx"))

		let zip = source.appending(component: "rocket-buddy.zip")
		let process = Process()
		process.executableURL = URL(filePath: "/usr/bin/zip")
		process.currentDirectoryURL = source
		process.arguments = ["-q", "-X", "-r", zip.path(percentEncoded: false), "rocket-buddy"]
		try process.run()
		process.waitUntilExit()
		return try Data(contentsOf: zip)
	}

	private func write(_ text: String, to url: URL) throws {
		try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data(text.utf8).write(to: url)
	}

	private func hook(in plugin: URL) throws -> String {
		try String(contentsOf: plugin.appending(path: "hooks/register.tsx"), encoding: .utf8)
	}

	private func sha256(_ data: Data) -> String {
		SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}
}
