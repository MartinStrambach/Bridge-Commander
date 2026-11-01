import Foundation
import ProcessExecution

/// An iPhone or iPad paired with this Mac, which the Run bar can build for instead of the
/// simulator the pane shows. Only run on: the pane's screen, input and MCP tools are the
/// simulator's.
public struct PhysicalDevice: Identifiable, Equatable, Sendable {
	/// The hardware UDID: what `xcodebuild -destination 'platform=iOS,id=…'` and
	/// `devicectl --device` both take. Not `devicectl`'s own `identifier`, which xcodebuild does
	/// not know.
	public var id: String
	/// The name the owner gave it ("Alex's iPhone"); several can share one.
	public var name: String
	/// What it is ("iPhone 17 Pro"), which tells apart devices with the same name.
	public var model: String
	public var osVersion: String?
	public var kind: Kind
	/// Reachable now, over a cable or the network, and paired. A device that is off, away or
	/// locked out of its tunnel is listed but cannot be run on.
	public var isAvailable: Bool
	/// Trusted by this Mac. One plugged in but not yet trusted is reachable and still cannot be
	/// built for, which the menu says rather than calling it not connected.
	public var isPaired: Bool

	public enum Kind: Equatable, Sendable {
		case iPhone
		case iPad
	}

	public init(id: String, name: String, model: String, osVersion: String?, kind: Kind, isAvailable: Bool, isPaired: Bool = true) {
		self.id = id
		self.name = name
		self.model = model
		self.osVersion = osVersion
		self.kind = kind
		self.isAvailable = isAvailable
		self.isPaired = isPaired
	}

	var systemImage: String {
		kind == .iPad ? "ipad" : "iphone"
	}
}

/// Lists paired devices with `devicectl list devices`, which is what Xcode's own device list
/// comes from. It answers in about 0.15 s from CoreDevice's cache, so the pane can poll it.
public nonisolated enum PhysicalDeviceList {
	/// Why the devices could not be listed: `devicectl` missing (an Xcode before 15) or failing,
	/// or a listing in a shape this code does not know (it is not a stable interface).
	public struct Failure: LocalizedError, Equatable {
		public var message: String

		public var errorDescription: String? {
			message
		}
	}

	/// The paired iOS and iPadOS devices, reachable ones first. Throws rather than answering
	/// none, so the menu does not claim nothing is paired when it could not tell.
	public static func devices() async throws -> [PhysicalDevice] {
		let output = FileManager.default.temporaryDirectory
			.appending(component: "devicectl-devices-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: output) }
		// `--json-output -` would mix the JSON with devicectl's own messages on stdout.
		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
			arguments: ["devicectl", "list", "devices", "--quiet", "--json-output", output.path(percentEncoded: false)]
		)
		guard result.success else {
			let detail = result.trimmedError.isEmpty ? "exit status \(result.exitCode)" : result.trimmedError
			throw Failure(message: "devicectl could not list devices: \(detail)")
		}
		guard let data = try? Data(contentsOf: output) else {
			throw Failure(message: "devicectl wrote no device list")
		}
		return try devices(inListJSON: data)
	}

	/// The physical iOS devices in `devicectl list devices --json-output`'s file. Simulators are
	/// in it too (`reality` "simulated"), and Apple Watches and Vision Pros under their own
	/// platforms; both are left out.
	static func devices(inListJSON data: Data) throws -> [PhysicalDevice] {
		struct Listing: Decodable {
			struct Result: Decodable {
				var devices: [Device]
			}

			struct Device: Decodable {
				struct Hardware: Decodable {
					var udid: String?
					var platform: String?
					var deviceType: String?
					var marketingName: String?
					var reality: String?
				}

				struct Properties: Decodable {
					var name: String?
					var osVersionNumber: String?
				}

				struct Connection: Decodable {
					var pairingState: String?
					var transportType: String?
				}

				var hardwareProperties: Hardware
				var deviceProperties: Properties?
				var connectionProperties: Connection?
			}

			var result: Result
		}

		guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else {
			throw Failure(message: "devicectl's device list is in a format this version does not read")
		}
		return listing.result.devices
			.compactMap { device -> PhysicalDevice? in
				let hardware = device.hardwareProperties
				// The UDID is typed into the run tab; anything but a UDID's characters is not one.
				guard
					hardware.reality == "physical", hardware.platform == "iOS", let udid = hardware.udid, !udid.isEmpty,
					udid.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") })
				else {
					return nil
				}
				let model = hardware.marketingName ?? hardware.deviceType ?? "iOS device"
				let connection = device.connectionProperties
				// A device out of reach has no transport; one never trusted cannot be built for.
				let isPaired = connection?.pairingState == "paired"
				let isAvailable = isPaired && connection?.transportType != nil
				return PhysicalDevice(
					id: udid,
					name: device.deviceProperties?.name ?? model,
					model: model,
					osVersion: device.deviceProperties?.osVersionNumber,
					kind: hardware.deviceType == "iPad" ? .iPad : .iPhone,
					isAvailable: isAvailable,
					isPaired: isPaired
				)
			}
			.sorted { lhs, rhs in
				if lhs.isAvailable != rhs.isAvailable {
					return lhs.isAvailable
				}
				return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
			}
	}
}
