import Foundation

/// Where the Run button builds for: the simulator the pane shows, or a device picked in the Run
/// bar.
public enum RunDestination: Equatable, Sendable {
	case simulator(SimulatorDevice)
	case device(PhysicalDevice)

	/// The simulator's UDID, or the device's hardware UDID: the `id` of xcodebuild's destination.
	public var id: String {
		switch self {
		case let .simulator(device):
			device.id
		case let .device(device):
			device.id
		}
	}

	public var name: String {
		switch self {
		case let .simulator(device):
			device.name
		case let .device(device):
			device.name
		}
	}

	/// The script's word for it.
	var kind: String {
		switch self {
		case .simulator:
			"simulator"
		case .device:
			"device"
		}
	}
}

/// What the pane's Run button types into a terminal tab: a script that builds a scheme for the
/// pane's simulator or a device, installs the app and launches it with its console attached, as
/// ⌘R in Xcode does without the debugger.
///
/// The work is in a script file rather than in the typed line, so the tab shows one short command
/// the user can read and run again by hand. The app writes the file each time it runs one, so it
/// always matches the app's version.
public nonisolated enum SimulatorRunCommand {
	static let scriptName = "run-ios-app.sh"

	/// The line typed into the tab.
	static func command(scriptPath: String, projectPath: String, scheme: XcodeScheme, destination: RunDestination) -> String {
		// A device's name is whatever its owner typed; a line break in it would leave the tab
		// at a continuation prompt.
		let name = destination.name.components(separatedBy: .newlines).joined(separator: " ")
		return ["/bin/bash", scriptPath, projectPath, scheme.name, scheme.productName ?? "", destination.kind, destination.id, name]
			.map(shellQuoted)
			.joined(separator: " ")
	}

	/// `value` single-quoted for a POSIX shell, so spaces and `$` in paths and names stay literal.
	/// A word of only safe characters is left bare to keep the line readable.
	static func shellQuoted(_ value: String) -> String {
		let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+=:,@"))
		if !value.isEmpty, value.unicodeScalars.allSatisfy({ $0.isASCII && safe.contains($0) }) {
			return value
		}
		return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
	}

	/// Writes the script to `folder` and returns the command that runs it for `scheme` on
	/// `destination`.
	static func prepare(in folder: URL, projectPath: String, scheme: XcodeScheme, destination: RunDestination) throws -> String {
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let scriptURL = folder.appending(component: scriptName)
		try script.write(to: scriptURL, atomically: true, encoding: .utf8)
		return command(scriptPath: scriptURL.path(percentEncoded: false), projectPath: projectPath, scheme: scheme, destination: destination)
	}

	/// Where the script is kept: the app's own Application Support folder, named by bundle id so
	/// the debug build keeps its own.
	static func defaultFolder() -> URL {
		let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
		let appSupport = urls.first ?? URL(fileURLWithPath: NSHomeDirectory())
			.appending(component: "Library/Application Support")
		return appSupport
			.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
			.appending(component: "Scripts")
	}

	/// bash, not the user's shell: macOS's bash 3.2 is always there and behaves the same for
	/// everyone. The build settings are read after the build because a build phase may generate
	/// what they depend on. They list each target the scheme builds; the app is the one named
	/// `product`, or with no product (a scheme Xcode made up) the first `.app`. An extension's
	/// scheme launches an app it may not list, which is looked for where the products go. That is
	/// Xcode's own derived data, so a build here and one in Xcode share their work. Ctrl-C reaches `simctl launch`, which
	/// passes it to the app; the trap terminates the app anyway, in case it ignores the signal.
	/// A device build passes `-allowProvisioningUpdates`, so automatic signing may register the
	/// device and fetch a profile as Xcode would; the app goes on with `devicectl`, whose
	/// `--console` forwards Ctrl-C to the app as `simctl launch` does.
	/// OSC 9 posts the outcome as the tab's notification, for a build left running in another tab.
	static let script = #"""
	#!/bin/bash
	# Written by Bridge Commander for the Run button beside the simulator: builds a scheme for a
	# simulator or a device, installs the app and launches it with its console in this terminal.
	# Usage: run-ios-app.sh <workspace-or-project> <scheme> <product.app or ""> <simulator|device> <udid> [device-name]
	set -uo pipefail

	container=$1 scheme=$2 product=$3 kind=$4 udid=$5 device=${6:-$5}
	case $container in
		*.xcworkspace) container_flag=-workspace ;;
		*) container_flag=-project ;;
	esac
	case $kind in
		simulator) destination="platform=iOS Simulator,id=$udid" build_flags=() ;;
		device) destination="platform=iOS,id=$udid" build_flags=(-allowProvisioningUpdates) ;;
		*) printf 'Unknown destination kind %s: expected simulator or device\n' "$kind" >&2; exit 2 ;;
	esac

	notify() { printf '\033]9;%s\007' "$1"; }
	step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }
	fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1"; notify "$1"; exit 1; }

	step "Building $scheme for $device"
	if command -v xcbeautify >/dev/null 2>&1; then
		xcodebuild "$container_flag" "$container" -scheme "$scheme" -destination "$destination" ${build_flags[@]+"${build_flags[@]}"} build | xcbeautify
	else
		printf 'Only warnings and errors are shown; install xcbeautify to follow the build.\n'
		xcodebuild -quiet "$container_flag" "$container" -scheme "$scheme" -destination "$destination" ${build_flags[@]+"${build_flags[@]}"} build
	fi || fail "Build of $scheme failed"

	settings=$(xcodebuild "$container_flag" "$container" -scheme "$scheme" -destination "$destination" -showBuildSettings -json 2>/dev/null) \
		|| fail "Could not read the build settings of $scheme"
	setting() { plutil -extract "$1.buildSettings.$2" raw - <<<"$settings" 2>/dev/null; }
	app=
	i=0
	while target_dir=$(setting "$i" TARGET_BUILD_DIR); do
		name=$(setting "$i" FULL_PRODUCT_NAME)
		if [ "$name" = "$product" ] || { [ -z "$product" ] && [ "${name%.app}" != "$name" ]; }; then
			app="$target_dir/$name"
			break
		fi
		i=$((i + 1))
	done
	if [ -z "$app" ] && [ -n "$product" ]; then
		app="$(setting 0 BUILT_PRODUCTS_DIR)/$product"
	fi
	[ -n "$app" ] && [ -d "$app" ] || fail "The app $scheme builds was not found${app:+ at $app}"
	product=${app##*/}
	bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist") \
		|| fail "$product has no bundle identifier"

	step "Installing $product on $device"
	if [ "$kind" = device ]; then
		xcrun devicectl device install app --quiet --device "$udid" "$app" \
			|| fail "Could not install $product on $device"
	else
		xcrun simctl bootstatus "$udid" -b >/dev/null || fail "Could not boot $device"
		xcrun simctl install "$udid" "$app" || fail "Could not install $product on $device"
	fi

	step "Launching $bundle_id (Ctrl-C stops it)"
	notify "$scheme is running on $device"
	if [ "$kind" = device ]; then
		# devicectl passes Ctrl-C on to the app and waits for it to end.
		trap 'step "Stopped"; exit 130' INT
		xcrun devicectl device process launch --console --terminate-existing --device "$udid" "$bundle_id"
	else
		trap 'xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1; step "Stopped"; exit 130' INT
		xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id"
	fi
	status=$?
	trap - INT
	step "$scheme exited ($status)"
	"""#
}
