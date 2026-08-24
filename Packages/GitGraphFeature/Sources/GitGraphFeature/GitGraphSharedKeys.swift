import Foundation
import Sharing

public nonisolated extension SharedReaderKey where Self == FileStorageKey<GitGraphColumnWidths> {
	static var gitGraphColumnWidths: Self {
		.fileStorage(applicationSupportURL(name: "gitGraphColumnWidths.json"))
	}
}

private nonisolated func applicationSupportURL(name: String) -> URL {
	let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
	let appSupport = urls.first ?? URL(fileURLWithPath: NSHomeDirectory())
		.appending(component: "Library/Application Support")
	return appSupport
		.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
		.appending(component: name)
}
