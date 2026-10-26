import Darwin
import Foundation

/// A mounted volume the dashboard offers to scan.
public struct DiskVolume: Equatable, Identifiable, Sendable {
	public var url: URL
	public var name: String
	public var totalCapacity: Int64
	/// Space the system would make available to an important write (purgeable space included).
	public var availableCapacity: Int64
	/// Allocated space the system would free for that write: local snapshots, caches and the
	/// like. Finder shows it as "purgeable", and it is where deleted bytes often go first.
	public var purgeableCapacity: Int64
	public var isStartupVolume: Bool
	public var isInternal: Bool

	public var id: URL { url }
	public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
	public var usedFraction: Double { totalCapacity > 0 ? Double(usedCapacity) / Double(totalCapacity) : 0 }

	public init(url: URL, name: String, totalCapacity: Int64, availableCapacity: Int64, purgeableCapacity: Int64 = 0, isStartupVolume: Bool, isInternal: Bool) {
		self.url = url
		self.name = name
		self.totalCapacity = totalCapacity
		self.availableCapacity = availableCapacity
		self.purgeableCapacity = purgeableCapacity
		self.isStartupVolume = isStartupVolume
		self.isInternal = isInternal
	}
}

/// What a volume reports as taken, measured as a scan of it finishes, so the scan can show the
/// difference between that and what it found (`DiskNode.hiddenSpace`).
public struct DiskVolumeUsage: Equatable, Sendable {
	/// The capacity minus the free space, purgeable space included: everything allocated in the
	/// volume's APFS container, which is what Finder's "used" counts.
	public var allocatedCapacity: Int64
	public var purgeableCapacity: Int64
	/// What the other volumes of the same container take: on the startup disk the VM, Preboot,
	/// Update and Recovery volumes, each counted by `statfs` as its own blocks.
	public var otherVolumesCapacity: Int64

	public init(allocatedCapacity: Int64, purgeableCapacity: Int64, otherVolumesCapacity: Int64) {
		self.allocatedCapacity = allocatedCapacity
		self.purgeableCapacity = purgeableCapacity
		self.otherVolumesCapacity = otherVolumesCapacity
	}
}

public enum DiskVolumeLister {
	/// The visible mounted volumes, the startup volume first.
	public static func volumes() -> [DiskVolume] {
		let keys: Set<URLResourceKey> = [
			.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
			.volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeIsBrowsableKey,
		]
		let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: .skipHiddenVolumes) ?? []
		return urls.compactMap { url -> DiskVolume? in
			guard
				let values = try? url.resourceValues(forKeys: keys),
				values.volumeIsBrowsable != false,
				let total = values.volumeTotalCapacity
			else {
				return nil
			}
			let available = values.volumeAvailableCapacityForImportantUsage ?? 0
			return DiskVolume(
				url: url,
				name: values.volumeName ?? url.lastPathComponent,
				totalCapacity: Int64(total),
				availableCapacity: available,
				purgeableCapacity: max(0, available - Int64(values.volumeAvailableCapacity ?? 0)),
				isStartupVolume: values.volumeIsRootFileSystem ?? false,
				isInternal: values.volumeIsInternal ?? false
			)
		}
		.sorted { lhs, rhs in
			if lhs.isStartupVolume != rhs.isStartupVolume {
				return lhs.isStartupVolume
			}
			return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
		}
	}

	/// What the volume mounted at `url` reports as taken, or nil when `url` is not a volume's
	/// root (a folder scan has no hidden space to show).
	///
	/// APFS volumes of one container report the container's capacity and free space, so the
	/// allocated space is the container's and includes every sibling volume; `statfs` tells a
	/// volume's own blocks (its `f_blocks` less `f_bfree`), which is how the siblings' share is
	/// found. The siblings are the mounted volumes with the same capacity and free space, hidden
	/// ones included. A scan of the startup volume reaches the Data volume through firmlinks, so
	/// that one is not a sibling of `/`.
	public static func usage(ofVolumeAt url: URL) -> DiskVolumeUsage? {
		let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeIsRootFileSystemKey]
		let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: []) ?? []
		let path = DiskLocation.key(for: url)
		guard
			let volume = mounted.first(where: { DiskLocation.key(for: $0) == path }),
			let values = try? volume.resourceValues(forKeys: keys),
			let total = values.volumeTotalCapacity,
			let free = values.volumeAvailableCapacity
		else {
			return nil
		}
		let isStartup = values.volumeIsRootFileSystem ?? false
		let otherVolumes = mounted
			.filter { other in
				guard DiskLocation.key(for: other) != path, !(isStartup && DiskLocation.key(for: other) == "/System/Volumes/Data") else { return false }
				guard let otherValues = try? other.resourceValues(forKeys: keys) else { return false }
				return otherValues.volumeTotalCapacity == total && otherValues.volumeAvailableCapacity == free
			}
			.reduce(Int64(0)) { $0 + ownBlocks(ofVolumeAt: $1) }
		return DiskVolumeUsage(
			allocatedCapacity: max(0, Int64(total) - Int64(free)),
			purgeableCapacity: max(0, (values.volumeAvailableCapacityForImportantUsage ?? 0) - Int64(free)),
			otherVolumesCapacity: otherVolumes
		)
	}

	/// The bytes a volume holds itself, from `statfs`; 0 when it cannot be asked.
	private static func ownBlocks(ofVolumeAt url: URL) -> Int64 {
		var status = statfs()
		guard statfs(url.path(percentEncoded: false), &status) == 0, status.f_blocks >= status.f_bfree else { return 0 }
		return Int64(status.f_blocks - status.f_bfree) * Int64(status.f_bsize)
	}
}
