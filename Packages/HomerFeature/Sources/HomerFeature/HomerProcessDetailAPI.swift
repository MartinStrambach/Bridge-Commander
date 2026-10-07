import Foundation

/// The process page's calls (`getProcess`, `getProcessLangGraph`, `resumeProcess`,
/// `listArtifacts`, `fetchArtifactContent`/`downloadArtifact` in the console's
/// `lib/api/client.ts`, and the log tail of `lib/api/streams.ts`).
extension HomerAPI {
	static func process(baseURL: String, id: Int) async throws -> HomerProcess {
		try await decode(HomerProcess.self, from: send("GET", "/api/v1/status/\(id)", baseURL: baseURL))
	}

	/// The run's LangGraph workflow, or nil when it has none (404). Without `graph` it is the
	/// cheap probe: no node states, no Mermaid source, nothing run on the server.
	static func langGraphStatus(baseURL: String, processId: Int, graph: Bool) async throws -> HomerLangGraphStatus? {
		do {
			let data = try await send(
				"GET",
				"/api/v1/processes/\(processId)/langgraph",
				baseURL: baseURL,
				queryItems: graph ? [URLQueryItem(name: "graph", value: "true")] : []
			)
			return try decode(HomerLangGraphStatus.self, from: data)
		}
		catch HomerAPIError.server(status: 404, _) {
			return nil
		}
	}

	/// Starts a new run from the workflow's last checkpoint and returns its id.
	static func resumeProcess(baseURL: String, id: Int) async throws -> Int {
		try await decode(
			HomerRetryResponse.self,
			from: send("POST", "/api/v1/processes/\(id)/resume", baseURL: baseURL, refusalsInServerWords: true)
		).processId
	}

	static func artifacts(baseURL: String, processId: Int) async throws -> [HomerArtifact] {
		let data = try await send(
			"GET",
			"/api/v1/artifacts/list",
			baseURL: baseURL,
			queryItems: [URLQueryItem(name: "processId", value: String(processId))]
		)
		return try decode(HomerArtifactListing.self, from: data).files
	}

	/// An artifact's bytes, and whether the run has finished writing it.
	static func artifact(baseURL: String, processId: Int, path: String) async throws -> (data: Data, isComplete: Bool) {
		let (data, response) = try await sendForResponse(
			"GET",
			"/api/v1/artifacts",
			baseURL: baseURL,
			queryItems: [
				URLQueryItem(name: "processId", value: String(processId)),
				URLQueryItem(name: "path", value: HomerArtifactPath.apiPath(path)),
			]
		)
		return (data, response.value(forHTTPHeaderField: "X-File-Complete") == "true")
	}

	static func artifactContent(baseURL: String, processId: Int, path: String) async throws -> HomerArtifactContent {
		let (data, isComplete) = try await artifact(baseURL: baseURL, processId: processId, path: path)
		return HomerArtifactContent(
			text: String(decoding: data, as: UTF8.self),
			byteCount: data.count,
			isComplete: isComplete
		)
	}

	/// Tails command `executionIndex`'s output from byte `offset` on: the server sends what the
	/// file holds past it, then new bytes as they are written, and ends once the run has.
	static func logEvents(
		baseURL: String,
		processId: Int,
		executionIndex: Int,
		stream: HomerOutputStream,
		offset: Int
	) -> AsyncThrowingStream<HomerLogEvent, any Error> {
		let events = HomerAPI.events(
			"/api/v1/stream/processes/\(processId)/logs",
			baseURL: baseURL,
			queryItems: [
				URLQueryItem(name: "cmd", value: String(executionIndex)),
				URLQueryItem(name: "stream", value: stream.apiValue),
			],
			// The byte offset to resume from (absent: from the start of the file).
			headers: [("Last-Event-ID", String(offset))]
		)
		return AsyncThrowingStream { continuation in
			let task = Task {
				do {
					for try await event in events {
						switch event.name {
						case "log.chunk":
							struct Chunk: Decodable {
								var content: String
							}
							guard let endOffset = event.id.flatMap(Int.init),
							      let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(event.data.utf8))
							else {
								continue
							}
							continuation.yield(.chunk(text: chunk.content, endOffset: endOffset))
						case "log.end":
							continuation.yield(.end)
						default:
							continue
						}
					}
					continuation.finish()
				}
				catch {
					continuation.finish(throwing: error)
				}
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}
}
