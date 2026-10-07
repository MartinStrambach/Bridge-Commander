import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer agent models")
struct HomerAgentModelsTests {
	/// The shape `GET /api/v1/agents` answers with: the backend encodes defaults and nulls
	/// (`apiJson`), sends `inputs` and the deprecated `queryParams` alias both, and encodes the
	/// transformer as a `type`-discriminated object. The typed-generation fields (`secret`,
	/// `values`, …) are left in to show they are ignored.
	private let agentsJSON = """
		{
		  "agents": [
		    {
		      "name": "factory",
		      "description": "Builds a feature from a YouTrack ticket",
		      "inputs": [
		        { "paramName": "ticket", "envName": "TICKET", "src": "query", "type": "STRING",
		          "required": true, "transformer": { "type": "pass" }, "secret": false,
		          "values": null, "pattern": null, "min": null, "max": null,
		          "minLength": null, "maxLength": null, "default": null },
		        { "paramName": "payload", "envName": "BRANCH", "src": "body", "type": "ANY",
		          "required": false, "transformer": { "type": "jsonPath", "path": "$.ref" } },
		        { "paramName": "X-Trace-Id", "envName": "TRACE_ID", "src": "header", "type": "integer",
		          "required": false, "transformer": { "type": "pass" } }
		      ],
		      "queryParams": null,
		      "scriptCount": 4,
		      "cron": {
		        "expression": "0 3 * * 1-5",
		        "timezone": "Europe/Prague",
		        "nextRunAt": 1760000000,
		        "lastRunAt": 1759900000,
		        "lastRunProcessId": 812
		      },
		      "writable": true
		    },
		    {
		      "name": "legacy",
		      "description": null,
		      "inputs": null,
		      "queryParams": [ { "paramName": "q" } ],
		      "scriptCount": 1,
		      "cron": null,
		      "writable": false
		    },
		    {
		      "name": "older-server",
		      "inputs": [ { "paramName": "x", "src": "carrier-pigeon" } ],
		      "scriptCount": 2
		    }
		  ]
		}
		"""

	@Test("the agent list decodes, with the inputs' defaults and the deprecated alias")
	func decodesAgents() throws {
		let agents = try JSONDecoder().decode(HomerAgentListResponse.self, from: Data(agentsJSON.utf8)).agents

		#expect(agents.map(\.name) == ["factory", "legacy", "older-server"])

		let factory = agents[0]
		#expect(factory.description == "Builds a feature from a YouTrack ticket")
		#expect(factory.scriptCount == 4)
		#expect(factory.isWritable)
		#expect(factory.cron == HomerAgent.Cron(
			expression: "0 3 * * 1-5",
			timezone: "Europe/Prague",
			nextRunAt: 1_760_000_000,
			lastRunAt: 1_759_900_000,
			lastRunProcessId: 812
		))
		#expect(factory.inputs == [
			HomerAgent.Input(paramName: "ticket", envName: "TICKET", source: .query, type: "STRING"),
			HomerAgent.Input(
				paramName: "payload",
				envName: "BRANCH",
				source: .body,
				type: "ANY",
				required: false,
				transformer: HomerAgent.Input.Transformer(type: "jsonPath", path: "$.ref")
			),
			HomerAgent.Input(paramName: "X-Trace-Id", envName: "TRACE_ID", source: .header, type: "integer", required: false),
		])
		#expect(factory.queryInputs.map(\.paramName) == ["ticket"])
		#expect(factory.bodyInputs.map(\.paramName) == ["payload"])
		#expect(factory.headerInputs.map(\.paramName) == ["X-Trace-Id"])

		// `inputs: null` falls back to `queryParams`, whose omitted fields take the backend's
		// defaults.
		let legacy = agents[1]
		#expect(legacy.description == nil)
		#expect(legacy.cron == nil)
		#expect(!legacy.isWritable)
		#expect(legacy.inputs == [HomerAgent.Input(paramName: "q", envName: "q", source: .query, type: "STRING", required: true)])

		// No `writable` (a server older than the field) and a source the app does not know: not
		// editable, and the input is kept but neither shown nor sent.
		let older = agents[2]
		#expect(!older.isWritable)
		#expect(older.inputs.map(\.source) == [.unknown])
		#expect(older.queryInputs.isEmpty)
	}

	@Test("a reload result decodes")
	func decodesReloadResult() throws {
		let json = """
			{ "added": ["new-agent"], "updated": ["factory"], "removed": [],
			  "errors": ["broken/agent.yaml: unknown command type 'shell'"] }
			"""
		let result = try JSONDecoder().decode(HomerAgentReloadResult.self, from: Data(json.utf8))

		#expect(result == HomerAgentReloadResult(
			added: ["new-agent"],
			updated: ["factory"],
			errors: ["broken/agent.yaml: unknown command type 'shell'"]
		))
		#expect(result.hasChanges)
		#expect(!HomerAgentReloadResult().hasChanges)
	}

	@Test("transformers are described as the console describes them")
	func transformerSummary() {
		typealias Transformer = HomerAgent.Input.Transformer
		#expect(Transformer.pass.summary == "Direct pass-through")
		#expect(Transformer(type: "jsonPath", path: "$.a").summary == "Extract JSON path: $.a")
		#expect(Transformer(type: "jsonPath").summary == "Extract JSON path: unknown")
		#expect(Transformer(type: "regex", pattern: "^v(\\d+)", group: 1).summary == "Regex match: ^v(\\d+) (group 1)")
		#expect(Transformer(type: "lua").summary == "Unknown transformer")
	}

	@Test("an agent's console route encodes its name as encodeURIComponent does")
	func consolePath() {
		#expect(HomerAgent(name: "factory-notify").consolePath == "agents/factory-notify")
		#expect(HomerAgent(name: "team/a b").consolePath == "agents/team%2Fa%20b")
	}

	// MARK: - Validation

	@Test("inputs are checked as the console checks them")
	func validation() {
		let string = HomerAgent.Input(paramName: "s", type: "STRING")
		#expect(HomerAgentInputValidation.error(for: string, value: " ") == "This field is required")
		#expect(HomerAgentInputValidation.error(for: string, value: "a b") == "String values cannot contain spaces")
		#expect(HomerAgentInputValidation.error(for: string, value: "MOB-1") == nil)

		let optional = HomerAgent.Input(paramName: "o", type: "STRING", required: false)
		#expect(HomerAgentInputValidation.error(for: optional, value: "") == nil)

		let number = HomerAgent.Input(paramName: "n", type: "NUMBER")
		#expect(HomerAgentInputValidation.error(for: number, value: "-42") == nil)
		#expect(HomerAgentInputValidation.error(for: number, value: "4.2") == "Must be a valid integer")
		#expect(HomerAgentInputValidation.error(for: number, value: "-") == "Must be a valid integer")
		#expect(HomerAgentInputValidation.error(for: number, value: "٤٢") == "Must be a valid integer")

		let any = HomerAgent.Input(paramName: "a", type: "ANY")
		#expect(HomerAgentInputValidation.error(for: any, value: "anything at all") == nil)

		// A typed input gets the required check only; the server validates the rest.
		let integer = HomerAgent.Input(paramName: "i", type: "integer")
		#expect(HomerAgentInputValidation.error(for: integer, value: "not a number") == nil)

		// A JSONPath input must be JSON, whatever its type says.
		let json = HomerAgent.Input(
			paramName: "j",
			type: "STRING",
			transformer: HomerAgent.Input.Transformer(type: "jsonPath", path: "$.a")
		)
		#expect(HomerAgentInputValidation.error(for: json, value: #"{"a": "b c"}"#) == nil)
		#expect(HomerAgentInputValidation.error(for: json, value: "42") == nil)
		#expect(
			HomerAgentInputValidation.error(for: json, value: "{a:") == "Must be valid JSON (JSONPath transformer requires JSON input)"
		)

		#expect(HomerAgentInputValidation.errors(for: [string, number, optional], values: ["n": "x"]) == [
			"s": "This field is required",
			"n": "Must be a valid integer",
		])
	}

	// MARK: - Run request

	private let runAgent = HomerAgent(
		name: "factory",
		inputs: [
			HomerAgent.Input(paramName: "ticket", source: .query),
			HomerAgent.Input(paramName: "note", source: .query, required: false),
			HomerAgent.Input(paramName: "ref", source: .body),
			HomerAgent.Input(paramName: "extra", source: .body, required: false),
			HomerAgent.Input(paramName: "X-Trace-Id", source: .header, required: false),
		]
	)

	@Test("a run sends each filled input by its source, and no empty one")
	func runRequest() {
		let request = HomerAgentRunRequest(
			agent: runAgent,
			values: ["ticket": "MOB-1+2", "note": "  ", "ref": "it's/main", "extra": "", "X-Trace-Id": "t-1"]
		)

		#expect(request == HomerAgentRunRequest(
			queryItems: [URLQueryItem(name: "ticket", value: "MOB-1+2")],
			bodyFields: [HomerAgentRunRequest.Field("ref", "it's/main")],
			headers: [HomerAgentRunRequest.Field("X-Trace-Id", "t-1")]
		))
		#expect(request.bodyJSON.flatMap { String(data: $0, encoding: .utf8) } == #"{"ref":"it's/main"}"#)
		// `+` would read as a space on the server.
		#expect(request.percentEncodedQueryItems == [URLQueryItem(name: "ticket", value: "MOB-1%2B2")])
	}

	@Test("an agent with body inputs always gets a JSON body; one without, none")
	func runRequestBody() {
		let empty = HomerAgentRunRequest(agent: runAgent, values: [:])
		#expect(empty.bodyJSON.flatMap { String(data: $0, encoding: .utf8) } == "{}")

		let queryOnly = HomerAgentRunRequest(agent: HomerAgent(name: "q", inputs: [HomerAgent.Input(paramName: "a")]), values: ["a": "1"])
		#expect(queryOnly.bodyJSON == nil)
	}

	@Test("the curl export single-quotes every argument")
	func curlCommand() {
		let request = HomerAgentRunRequest(
			agent: runAgent,
			values: ["ticket": "MOB-1", "ref": "it's $HOME", "X-Trace-Id": "t-1"]
		)

		#expect(request.curlCommand(baseURL: "https://homer.example.com", agentName: "factory") == """
			curl -X POST 'https://homer.example.com/api/v1/agent/factory?ticket=MOB-1' \\
			  -H 'X-Trace-Id: t-1' \\
			  -H 'Content-Type: application/json' \\
			  -d '{"ref":"it'\\''s $HOME"}'
			""")
		#expect(
			HomerAgentRunRequest().curlCommand(baseURL: "http://localhost:8080", agentName: "a b")
				== "curl -X POST 'http://localhost:8080/api/v1/agent/a%20b'"
		)
	}
}
