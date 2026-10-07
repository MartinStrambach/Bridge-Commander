import AppKit
import ComposableArchitecture
import Foundation

/// The process page's part of the Homer API. Errors are `HomerAPIError`s.
@DependencyClient
public struct HomerProcessDetailClient: Sendable {
	public var process: @Sendable (_ baseURL: String, _ id: Int) async throws -> HomerProcess
	/// The run's LangGraph workflow, nil when it has none. `graph` adds the node states.
	public var langGraphStatus: @Sendable (_ baseURL: String, _ processId: Int, _ graph: Bool) async throws -> HomerLangGraphStatus?
	/// Returns the new run's id.
	public var resumeProcess: @Sendable (_ baseURL: String, _ id: Int) async throws -> Int
	public var artifacts: @Sendable (_ baseURL: String, _ processId: Int) async throws -> [HomerArtifact]
	public var artifactContent: @Sendable (_ baseURL: String, _ processId: Int, _ path: String) async throws -> HomerArtifactContent
	/// Tails a command's output from a byte offset on.
	public var logEvents: @Sendable (
		_ baseURL: String,
		_ processId: Int,
		_ executionIndex: Int,
		_ stream: HomerOutputStream,
		_ offset: Int
	) -> AsyncThrowingStream<HomerLogEvent, any Error> = { _, _, _, _, _ in .finished() }
	/// Saves an artifact to the Downloads folder, as the console's browser download does, shows
	/// it in Finder and returns where it went.
	public var downloadArtifact: @Sendable (_ baseURL: String, _ processId: Int, _ path: String) async throws -> URL
}

extension HomerProcessDetailClient: DependencyKey {
	public static let liveValue = HomerProcessDetailClient(
		process: { try await HomerAPI.process(baseURL: $0, id: $1) },
		langGraphStatus: { try await HomerAPI.langGraphStatus(baseURL: $0, processId: $1, graph: $2) },
		resumeProcess: { try await HomerAPI.resumeProcess(baseURL: $0, id: $1) },
		artifacts: { try await HomerAPI.artifacts(baseURL: $0, processId: $1) },
		artifactContent: { try await HomerAPI.artifactContent(baseURL: $0, processId: $1, path: $2) },
		logEvents: {
			HomerAPI.logEvents(baseURL: $0, processId: $1, executionIndex: $2, stream: $3, offset: $4)
		},
		downloadArtifact: { baseURL, processId, path in
			let (data, _) = try await HomerAPI.artifact(baseURL: baseURL, processId: processId, path: path)
			let url = try HomerDownloads.save(data, named: HomerArtifactPath.fileName(path))
			await MainActor.run {
				NSWorkspace.shared.activateFileViewerSelecting([url])
			}
			return url
		}
	)
}

extension HomerProcessDetailClient: TestDependencyKey {
	public static let testValue = HomerProcessDetailClient()
}

nonisolated enum HomerDownloads {
	/// Writes into the user's Downloads folder under the file's own name, numbered like a
	/// browser's (`report 2.json`) when the name is taken.
	static func save(_ data: Data, named fileName: String) throws -> URL {
		let folder = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		let url = availableURL(in: folder, fileName: fileName) { FileManager.default.fileExists(atPath: $0.path) }
		try data.write(to: url, options: .withoutOverwriting)
		return url
	}

	static func availableURL(in folder: URL, fileName: String, exists: (URL) -> Bool) -> URL {
		let candidate = folder.appending(path: fileName)
		guard exists(candidate) else {
			return candidate
		}
		let name = (fileName as NSString).deletingPathExtension
		let fileExtension = (fileName as NSString).pathExtension
		var number = 2
		while true {
			let numbered = fileExtension.isEmpty ? "\(name) \(number)" : "\(name) \(number).\(fileExtension)"
			let url = folder.appending(path: numbered)
			if !exists(url) {
				return url
			}
			number += 1
		}
	}
}
