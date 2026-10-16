import Foundation

/// A mounted volume the dashboard offers to scan.
public struct DiskVolume: Equatable, Identifiable, Sendable {
	public var url: URL
	public var name: String
	public var totalCapacity: Int64
	/// Space the system would make available to an important write (purgeable space included).
	public var availableCapacity: Int64
	public var isStartupVolume: Bool
	public var isInternal: Bool

	public var id: URL { url }
	public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
	public var usedFraction: Double { totalCapacity > 0 ? Double(usedCapacity) / Double(totalCapacity) : 0 }

	public init(url: URL, name: String, totalCapacity: Int64, availableCapacity: Int64, isStartupVolume: Bool, isInternal: Bool) {
		self.url = url
		self.name = name
		self.totalCapacity = totalCapacity
		self.availableCapacity = availableCapacity
		self.isStartupVolume = isStartupVolume
		self.isInternal = isInternal
	}
}

public enum DiskVolumeLister {
	/// The visible mounted volumes, the startup volume first.
	public static func volumes() -> [DiskVolume] {
		let keys: Set<URLResourceKey> = [
			.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
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
			return DiskVolume(
				url: url,
				name: values.volumeName ?? url.lastPathComponent,
				totalCapacity: Int64(total),
				availableCapacity: values.volumeAvailableCapacityForImportantUsage ?? 0,
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
}
