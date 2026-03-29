import Foundation
import Synchronization

/// Thread-safe data collector for reading from Process pipes
/// Prevents pipe buffer overflow by collecting data incrementally
public final nonisolated class PipeDataCollector: Sendable {
	private let data = Mutex<Data>(Data())

	public init() {}

	public func append(_ newData: Data) {
		data.withLock { $0.append(newData) }
	}

	public func getData() -> Data {
		data.withLock { $0 }
	}
}
