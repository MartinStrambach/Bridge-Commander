import ComposableArchitecture
import Foundation

/// One command's output (`view-artifact-dialog.tsx`): its stdout and stderr, a Claude command's
/// stdout read as the conversation, and live while the command still writes it.
///
/// The file is read once over REST, and while the server says it is not complete, tailed from
/// the byte the read ended at — the log stream resumes from any offset (`Last-Event-ID`), so
/// nothing is fetched twice. The console instead streams from byte 0 and swaps buffers.
@Reducer
public struct HomerProcessOutputReducer: Sendable {
	/// How long the tail waits before reconnecting, doubling up to `maxReconnectDelay`.
	static let reconnectDelay: Duration = .seconds(1)
	static let maxReconnectDelay: Duration = .seconds(30)
	static let maxReconnectAttempts = 6

	public enum Mode: Equatable, Sendable {
		/// Claude's messages and tool calls.
		case conversation
		case raw
	}

	public struct Output: Equatable, Sendable {
		public var text = ""
		/// Bytes of the file `text` holds — where the tail resumes.
		var byteCount = 0
		public var isComplete = true
		public var transcript = HomerClaudeTranscript()
		public var isLoading = false
		public var isTailing = false
		public var error: String?
		public var hasLoaded = false

		public init() {}
	}

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public let processId: Int
		public let executionIndex: Int
		/// The files of each stream; a stream without one has no output to show.
		public let paths: [HomerOutputStream: String]
		public var stream: HomerOutputStream
		/// Picked by the user; nil follows the output: the conversation for Claude's.
		public var mode: Mode?
		public internal(set) var outputs: [HomerOutputStream: Output] = [:]
		/// The command is still running — its files may not exist yet.
		public let isLiveCommand: Bool
		/// When the running command started, for the live header's clock.
		public let commandStart: Double?

		public init(
			baseURL: String,
			processId: Int,
			executionIndex: Int,
			paths: [HomerOutputStream: String],
			stream: HomerOutputStream,
			isLiveCommand: Bool = false,
			commandStart: Double? = nil
		) {
			self.baseURL = baseURL
			self.processId = processId
			self.executionIndex = executionIndex
			self.paths = paths
			self.stream = stream
			self.isLiveCommand = isLiveCommand
			self.commandStart = commandStart
		}

		public var output: Output {
			outputs[stream] ?? Output()
		}

		public var path: String? {
			paths[stream]
		}

		public var effectiveMode: Mode {
			mode ?? (output.transcript.isClaude ? .conversation : .raw)
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case task
		case refreshTapped
		case loaded(HomerOutputStream, Result<Loaded, any Error>)
		case logEvent(HomerOutputStream, HomerLogEvent)
		case tailStopped(HomerOutputStream, failure: String?)
		case delegate(Delegate)

		public enum Delegate: Equatable, Sendable {
			case unauthorized
		}
	}

	/// A read of the file, parsed off the main actor.
	public struct Loaded: Equatable, Sendable {
		var content: HomerArtifactContent
		var transcript: HomerClaudeTranscript
	}

	private nonisolated enum CancelID: Hashable {
		case load
		case tail
	}

	@Dependency(HomerProcessDetailClient.self)
	private var client

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding(\.stream):
				// Each stream decides its own mode, as the console resets it on a tab switch.
				state.mode = nil
				return load(&state)

			case .binding:
				return .none

			case .task, .refreshTapped:
				return load(&state)

			case let .loaded(stream, .success(loaded)):
				var output = Output()
				output.text = loaded.content.text
				output.byteCount = loaded.content.byteCount
				output.isComplete = loaded.content.isComplete
				output.transcript = loaded.transcript
				output.hasLoaded = true
				state.outputs[stream] = output
				return output.isComplete ? .none : tail(&state, stream: stream)

			case let .loaded(stream, .failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				// A running command's file appears with its first byte: until then the tail
				// waits for it.
				if state.isLiveCommand, case .server(status: 404, _) = error as? HomerAPIError {
					var output = Output()
					output.isComplete = false
					output.hasLoaded = true
					state.outputs[stream] = output
					return tail(&state, stream: stream)
				}
				state.outputs[stream, default: Output()].isLoading = false
				state.outputs[stream, default: Output()].error = error.localizedDescription
				return .none

			case let .logEvent(stream, .chunk(text, endOffset)):
				guard let byteCount = state.outputs[stream]?.byteCount, endOffset > byteCount else {
					return .none
				}
				// In place: a copy of the output would copy the whole log for every chunk.
				state.outputs[stream]?.text += text
				state.outputs[stream]?.byteCount = endOffset
				state.outputs[stream]?.transcript.append(text)
				return .none

			case let .logEvent(stream, .end):
				state.outputs[stream]?.isComplete = true
				state.outputs[stream]?.isTailing = false
				return .none

			case let .tailStopped(stream, failure):
				state.outputs[stream]?.isTailing = false
				if let failure {
					state.outputs[stream]?.error = failure
				}
				return .none

			case .delegate:
				return .none
			}
		}
	}

	private func load(_ state: inout State) -> Effect<Action> {
		let stream = state.stream
		guard let path = state.path else {
			return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.tail))
		}
		state.outputs[stream, default: Output()].isLoading = true
		state.outputs[stream, default: Output()].error = nil
		return .merge(
			.cancel(id: CancelID.tail),
			.run { [baseURL = state.baseURL, processId = state.processId] send in
				await send(.loaded(stream, Result {
					let content = try await client.artifactContent(baseURL, processId, path)
					return Loaded(content: content, transcript: HomerClaudeTranscript(parsing: content.text))
				}))
			}
			.cancellable(id: CancelID.load, cancelInFlight: true)
		)
	}

	/// Follows the file from where the read ended until the server says the run is over,
	/// reconnecting from the last byte received when the connection drops.
	private func tail(_ state: inout State, stream: HomerOutputStream) -> Effect<Action> {
		guard let output = state.outputs[stream] else {
			return .none
		}
		state.outputs[stream]?.isTailing = true
		return .run { [baseURL = state.baseURL, processId = state.processId, index = state.executionIndex, start = output.byteCount] send in
			var offset = start
			var failures = 0
			while true {
				do {
					for try await event in client.logEvents(baseURL, processId, index, stream, offset) {
						if case let .chunk(_, endOffset) = event {
							offset = endOffset
							failures = 0
						}
						await send(.logEvent(stream, event))
						if event == .end {
							return
						}
					}
				}
				catch HomerAPIError.unauthorized {
					await send(.delegate(.unauthorized))
					return
				}
				catch {
					failures += 1
					if failures > Self.maxReconnectAttempts {
						await send(.tailStopped(stream, failure: "Live output stopped: \(error.localizedDescription)"))
						return
					}
				}
				let delay = Self.reconnectDelay * (1 << min(failures, 5))
				try await clock.sleep(for: min(delay, Self.maxReconnectDelay))
			}
		}
		.cancellable(id: CancelID.tail, cancelInFlight: true)
	}
}
