import CoreServices
import Foundation

/// A thin wrapper over an `FSEventStream` with per-file events.
///
/// FSEvents rather than a `DispatchSource` per file: git replaces `HEAD`, `index` and refs by
/// writing a `.lock` file and renaming it over the original, so a source watching the file's
/// descriptor fires once and then watches an inode that is gone. FSEvents watches by path,
/// recursively, and survives the rename.
nonisolated final class FileSystemEventStream: @unchecked Sendable {
	private final class Handler: Sendable {
		let deliver: @Sendable ([FileSystemEvent]) -> Void

		init(_ deliver: @escaping @Sendable ([FileSystemEvent]) -> Void) {
			self.deliver = deliver
		}
	}

	private let stream: FSEventStreamRef
	private let queue = DispatchQueue(label: "BridgeCommander.FileSystemEventStream")
	private let handler: Unmanaged<Handler>

	/// - Parameter latency: Events within this many seconds of the first are delivered as one
	///   batch, so a checkout touching hundreds of files arrives as a handful of callbacks.
	init?(
		paths: [String],
		latency: TimeInterval,
		deliver: @escaping @Sendable ([FileSystemEvent]) -> Void
	) {
		let handler = Unmanaged.passRetained(Handler(deliver))
		var context = FSEventStreamContext(
			version: 0,
			info: handler.toOpaque(),
			retain: nil,
			release: nil,
			copyDescription: nil
		)
		let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
		guard
			let stream = FSEventStreamCreate(
				kCFAllocatorDefault,
				Self.callback,
				&context,
				paths as CFArray,
				FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
				latency,
				flags
			)
		else {
			handler.release()
			return nil
		}

		self.stream = stream
		self.handler = handler
		FSEventStreamSetDispatchQueue(stream, queue)
	}

	func start() {
		FSEventStreamStart(stream)
	}

	/// Stops delivery and frees the stream. Runs on the stream's queue, so it cannot race a
	/// callback that is already under way — the handler is released only after the last one.
	func stop() {
		queue.async { [self] in
			FSEventStreamStop(stream)
			FSEventStreamInvalidate(stream)
			FSEventStreamRelease(stream)
			handler.release()
		}
	}

	private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
		guard let info, let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else {
			return
		}

		let handler = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue()
		let lifecycle = FSEventStreamEventFlags(
			kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
		)
		let dropped = FSEventStreamEventFlags(
			kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
				| kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
		)
		let events = (0 ..< min(count, paths.count)).map { index in
			FileSystemEvent(
				path: paths[index],
				isCreatedOrRemoved: flags[index] & lifecycle != 0,
				mustRescan: flags[index] & dropped != 0
			)
		}
		handler.deliver(events)
	}
}
