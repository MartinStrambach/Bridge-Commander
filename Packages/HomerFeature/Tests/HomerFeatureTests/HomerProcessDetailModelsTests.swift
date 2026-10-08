import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer process page models")
struct HomerProcessDetailModelsTests {
	@Test("a process's page fields decode: execution files, runner times, Langfuse trace")
	func decodesProcessDetail() throws {
		let json = """
			{
			  "id": 7, "status": "FAILED", "agentName": "factory",
			  "history": [{ "timestamp": 1700000000, "status": "CREATED" }],
			  "executions": [
			    { "label": "build", "start": 1700000010, "end": 1700000075, "resultCode": 2,
			      "stdOut": "/tmp/homer/workspace-7/artifacts/cmd_0.out",
			      "stdErr": "/tmp/homer/workspace-7/artifacts/cmd_0.err", "errMsg": "exit 2" }
			  ],
			  "currentCommand": null, "currentCommandStart": 1700000080, "purgeAt": null,
			  "runner": {
			    "alias": "k8s-dev", "podName": "homer-7", "podPhase": "FAILED", "createdAt": 1700000001,
			    "startupFailure": { "reason": "ImagePullBackOff", "message": "no such image", "events": ["pulled"] }
			  },
			  "langfuseTraceUrl": "https://langfuse.example.com/trace/7"
			}
			"""

		let process = try JSONDecoder().decode(HomerProcess.self, from: Data(json.utf8))

		let execution = try #require(process.executions.first)
		#expect(execution.start == 1_700_000_010)
		#expect(execution.end == 1_700_000_075)
		#expect(execution.stdOut == "/tmp/homer/workspace-7/artifacts/cmd_0.out")
		#expect(execution.errMsg == "exit 2")
		#expect(process.currentCommandStart == 1_700_000_080)
		#expect(process.runner?.createdAt == 1_700_000_001)
		#expect(process.runner?.startupFailure == .init(reason: "ImagePullBackOff", message: "no such image", events: ["pulled"]))
		#expect(process.langfuseTraceUrl == "https://langfuse.example.com/trace/7")
		#expect(process.isResumeEligible)
	}

	@Test("artifact paths: an execution's absolute path is cut to its name, a listed one kept")
	func artifactPaths() {
		#expect(HomerArtifactPath.apiPath("/tmp/homer/workspace-7/artifacts/cmd_0.out") == "cmd_0.out")
		#expect(HomerArtifactPath.apiPath("reports/summary.json") == "reports/summary.json")
		#expect(HomerArtifactPath.fileName("reports/summary.json") == "summary.json")
		#expect(HomerArtifactPath.liveOutput(executionIndex: 3, stream: .stderr) == "cmd_3.err")
	}

	@Test("workflow nodes come in the order the Mermaid source declares them")
	func workflowNodeOrder() throws {
		let json = #"""
			{
			  "label": "workflow", "module": "flow", "threadId": "t-1",
			  "mermaid": "graph TD;\n\t__start__([<p>__start__</p>]):::first\n\tplan(plan)\n\tfan\\20out(fan out)\n\treview(review)\n\t__start__ --> plan;\n\tplan --> fan\\20out;\n",
			  "nodes": { "review": "pending", "fan out": "parked", "plan": "done" },
			  "subs": { "fan out": [
			    { "interruptId": "i-1", "processId": 8, "agentName": "worker", "status": "FINISHED",
			      "commands": [{ "label": "run", "state": "ok" }] },
			    { "interruptId": "i-2", "processId": 9, "agentName": "worker", "status": "FINISHED" }
			  ] }
			}
			"""#

		let status = try JSONDecoder().decode(HomerLangGraphStatus.self, from: Data(json.utf8))

		#expect(status.nodes.map(\.name) == ["plan", "fan out", "review"])
		#expect(status.subsFinished(node: "fan out"))
		#expect(!status.subsFinished(node: "plan"))
		#expect(status.allSubs.map(\.sub.interruptId) == ["i-1", "i-2"])
	}

	@Test("workflow nodes come in the topology's order, ahead of the Mermaid source's; taken edges by node")
	func workflowNodeOrderFromTopology() throws {
		let json = #"""
			{
			  "label": "workflow", "module": "flow", "threadId": "t-1",
			  "topology": {
			    "nodes": [{ "id": "__start__" }, { "id": "review" }, { "id": "fan out" }, { "id": "plan" }, { "id": "__end__" }],
			    "edges": [
			      { "source": "__start__", "target": "review", "label": null, "conditional": false },
			      { "source": "review", "target": "fan out", "conditional": true },
			      { "source": "review", "target": "plan", "label": "retry", "conditional": true }
			    ]
			  },
			  "mermaid": "graph TD;\n\tplan(plan)\n\tfan\\20out(fan out)\n\treview(review)\n",
			  "nodes": { "plan": "pending", "fan out": "parked", "review": "done", "extra": "pending" },
			  "traversed": [
			    { "source": "__start__", "target": "review" },
			    { "source": "review", "target": "fan out" },
			    { "source": "review", "target": "plan" }
			  ]
			}
			"""#

		let status = try JSONDecoder().decode(HomerLangGraphStatus.self, from: Data(json.utf8))

		#expect(status.nodes.map(\.name) == ["review", "fan out", "plan", "extra"])
		#expect(status.takenTargets(from: "review") == ["fan out", "plan"])
		#expect(status.takenTargets(from: "plan").isEmpty)
		#expect(status.hasGraph)
	}

	@Test("without a topology or Mermaid source the nodes are listed by name, with no graph")
	func workflowNodesWithoutGraph() {
		let status = HomerLangGraphStatus(label: "workflow", threadId: "t", nodeStates: ["b": "done", "a": "pending"])

		#expect(status.nodes.map(\.name) == ["a", "b"])
		#expect(!status.hasGraph)
		#expect(status.takenTargets(from: "a").isEmpty)
	}

	@Test("Mermaid node ids escape like langchain's `_to_safe_id`")
	func mermaidSafeID() {
		#expect(HomerLangGraphStatus.mermaidSafeID("plan_step-2") == "plan_step-2")
		#expect(HomerLangGraphStatus.mermaidSafeID("fan out.v2") == "fan\\20out\\2ev2")
	}

	@Test("a server-sent event is its fields up to the blank line; comments are skipped")
	func serverSentEvents() {
		var parser = HomerServerSentEventParser()
		var events: [HomerServerSentEvent] = []
		for line in [": ping", "event: log.chunk", "id: 42", #"data: {"content":"hi"}"#, "", "", "event: log.end", "data: {}", ""] {
			if let event = parser.consume(line: line) {
				events.append(event)
			}
		}

		#expect(events == [
			HomerServerSentEvent(name: "log.chunk", id: "42", data: #"{"content":"hi"}"#),
			HomerServerSentEvent(name: "log.end", id: nil, data: "{}"),
		])
	}

	@Test("a download takes the next free name, as a browser's does")
	func downloadName() {
		let folder = URL(filePath: "/Users/me/Downloads")
		let taken: Set<String> = ["report.json", "report 2.json", "notes"]

		let report = HomerDownloads.availableURL(in: folder, fileName: "report.json") { taken.contains($0.lastPathComponent) }
		let notes = HomerDownloads.availableURL(in: folder, fileName: "notes") { taken.contains($0.lastPathComponent) }
		let fresh = HomerDownloads.availableURL(in: folder, fileName: "cmd_0.out") { taken.contains($0.lastPathComponent) }

		#expect(report.lastPathComponent == "report 3.json")
		#expect(notes.lastPathComponent == "notes 2")
		#expect(fresh.lastPathComponent == "cmd_0.out")
	}

	@Test("a command's duration reads like the console's")
	func duration() {
		#expect(HomerFormat.duration(from: 100, to: 105) == "5s")
		#expect(HomerFormat.duration(from: 100, to: 225) == "2m 5s")
		#expect(HomerFormat.duration(from: 0, to: 3725) == "1h 2m 5s")
	}
}

@Suite("Claude conversation transcript")
struct HomerClaudeTranscriptTests {
	private let lines = [
		#"{"type":"system","subtype":"hook_started"}"#,
		#"{"type":"system","subtype":"init","model":"claude-opus-5-5"}"#,
		#"{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"Looking."}],"usage":{"input_tokens":10,"output_tokens":2}}}"#,
		#"{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}],"usage":{"input_tokens":12,"output_tokens":5}}}"#,
		#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"a.txt"}]}]}}"#,
		#"{"type":"assistant","message":{"id":"m2","content":[{"type":"text","text":"Done."}]}}"#,
		#"{"type":"result","subtype":"success","is_error":false,"duration_ms":4200,"duration_api_ms":3100,"num_turns":2,"total_cost_usd":0.0123,"result":"Done.","usage":{"input_tokens":20,"output_tokens":9,"cache_read_input_tokens":100,"cache_creation_input_tokens":0}}"#,
	]

	@Test("stream-json reads as messages and tool calls with their results")
	func parses() {
		let transcript = HomerClaudeTranscript(parsing: lines.joined(separator: "\n") + "\n")

		#expect(transcript.isClaude)
		#expect(transcript.model == "claude-opus-5-5")
		#expect(transcript.turns == 2)
		#expect(transcript.items.map(\.id) == ["message-0", "tool-t1", "message-2"])
		guard case let .tool(tool) = transcript.items[1] else {
			Issue.record("expected a tool call")
			return
		}
		#expect(tool.name == "Bash")
		#expect(tool.inputPreview == #"{"command":"ls"}"#)
		#expect(tool.result == "a.txt")
		#expect(transcript.lastMessageIndex == 2)
		#expect(transcript.inflightToolID == nil)
		#expect(transcript.outcome?.costUsd == 0.0123)
		#expect(transcript.outcome?.cacheReadTokens == 100)
		#expect(transcript.outcome?.turns == 2)
	}

	@Test("appending in pieces, mid-line included, ends where parsing it whole does")
	func appendsInPieces() {
		let text = lines.joined(separator: "\n") + "\n"
		var transcript = HomerClaudeTranscript()
		var rest = Substring(text)
		while !rest.isEmpty {
			let piece = rest.prefix(37)
			transcript.append(String(piece))
			rest = rest.dropFirst(piece.count)
		}

		#expect(transcript == HomerClaudeTranscript(parsing: text))
	}

	@Test("a tool call without a result yet is in flight; the running usage is the latest")
	func live() {
		let transcript = HomerClaudeTranscript(parsing: lines.prefix(4).joined(separator: "\n"))

		#expect(transcript.inflightToolID == "t1")
		#expect(transcript.outcome == nil)
		#expect(transcript.runningUsage?.input == 12)
		#expect(transcript.runningUsage?.output == 5)
	}

	@Test("output without Claude's init event is not a conversation")
	func notClaude() {
		let transcript = HomerClaudeTranscript(parsing: "Compiling…\nBuild succeeded\n")

		#expect(!transcript.isClaude)
		#expect(transcript.items.isEmpty)
	}
}
