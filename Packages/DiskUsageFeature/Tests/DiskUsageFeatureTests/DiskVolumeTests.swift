import Foundation
import Testing
@testable import DiskUsageFeature

@Suite("Disk volumes")
struct DiskVolumeTests {
	@Test("the startup volume reports what it has allocated; a folder is no volume")
	func usage() throws {
		let usage = try #require(DiskVolumeLister.usage(ofVolumeAt: URL(filePath: "/")))
		#expect(usage.allocatedCapacity > 0)
		#expect(usage.purgeableCapacity >= 0)
		#expect(usage.otherVolumesCapacity >= 0)
		// The siblings can never hold more than the container has allocated.
		#expect(usage.otherVolumesCapacity + usage.purgeableCapacity <= usage.allocatedCapacity)
		#expect(DiskVolumeLister.usage(ofVolumeAt: FileManager.default.temporaryDirectory) == nil)
	}

	@Test("a location has one spelling: standardized, without a trailing slash")
	func locationKey() {
		#expect(DiskLocation.key(for: URL(filePath: "/Users/me/", directoryHint: .isDirectory)) == "/Users/me")
		#expect(DiskLocation.key(for: URL(filePath: "/Users/me/../me")) == "/Users/me")
		#expect(DiskLocation.key(for: URL(filePath: "/")) == "/")
	}
}
