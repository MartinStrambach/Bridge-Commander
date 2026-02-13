import Foundation
import Synchronization

/// Thread-safe data collector for reading from Process pipes
/// Prevents pipe buffer overflow by collecting data incrementally
final nonisolated class PipeDataCollector: Sendable {
	private let data = Mutex<Data>(Data())

	func append(_ newData: Data) {
		data.withLock { $0.append(newData) }
	}

	func getData() -> Data {
		data.withLock { $0 }
	}
}
