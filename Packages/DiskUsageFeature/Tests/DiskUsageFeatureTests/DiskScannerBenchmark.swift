import Foundation
import Testing
@testable import DiskUsageFeature

/// Times a scan of a real folder. Skipped unless `DISK_SCAN_BENCHMARK_ROOT` names one:
///
///     DISK_SCAN_BENCHMARK_ROOT=~/Library/Developer swift test --filter DiskScannerBenchmark
///
/// Run it twice and read the second time: the first warms the kernel's caches.
/// `DISK_SCAN_BENCHMARK_WORKERS` overrides the number of worker threads.
@Suite("Disk scanner benchmark", .serialized)
struct DiskScannerBenchmark {
	@Test("scans the folder named by DISK_SCAN_BENCHMARK_ROOT", .enabled(if: ProcessInfo.processInfo.environment["DISK_SCAN_BENCHMARK_ROOT"] != nil))
	func scanTime() async throws {
		let path = try #require(ProcessInfo.processInfo.environment["DISK_SCAN_BENCHMARK_ROOT"])
		let root = URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
		let workers = ProcessInfo.processInfo.environment["DISK_SCAN_BENCHMARK_WORKERS"].flatMap(Int.init) ?? DiskScanner.workerCount
		for run in 1 ... 2 {
			for await event in DiskScanner.scan(root, workers: workers) {
				if case let .finished(result) = event {
					let gigabytes = Double(result.root.size) / 1_000_000_000
					print("run \(run), \(workers) workers: \(result.duration) for \(result.root.itemCount) items, \(result.root.size) bytes (\(String(format: "%.1f", gigabytes)) GB), \(result.inaccessibleFolders) unreadable folders")
				}
			}
		}
	}
}
