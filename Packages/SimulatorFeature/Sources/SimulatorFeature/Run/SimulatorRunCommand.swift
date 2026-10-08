import Foundation

/// What the pane's Run button types into a terminal tab: a script that builds a scheme for the
/// pane's simulator, installs the app and launches it with its console attached, as ⌘R in Xcode
/// does without the debugger.
///
/// The work is in a script file rather than in the typed line, so the tab shows one short command
/// the user can read and run again by hand. The app writes the file each time it runs one, so it
/// always matches the app's version.
public nonisolated enum SimulatorRunCommand {
	static let scriptName = "run-ios-app.sh"

	/// The line typed into the tab.
	static func command(scriptPath: String, projectPath: String, scheme: XcodeScheme, device: SimulatorDevice) -> String {
		["/bin/bash", scriptPath, projectPath, scheme.name, scheme.productName ?? "", device.id, device.name]
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
	/// `device`.
	static func prepare(in folder: URL, projectPath: String, scheme: XcodeScheme, device: SimulatorDevice) throws -> String {
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let scriptURL = folder.appending(component: scriptName)
		try script.write(to: scriptURL, atomically: true, encoding: .utf8)
		return command(scriptPath: scriptURL.path(percentEncoded: false), projectPath: projectPath, scheme: scheme, device: device)
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
	/// OSC 9 posts the outcome as the tab's notification, for a build left running in another tab.
	static let script = #"""
	#!/bin/bash
	# Written by Bridge Commander for the simulator pane's Run button: builds a scheme for a
	# simulator, installs the app and launches it with its console in this terminal.
	# Usage: run-ios-app.sh <workspace-or-project> <scheme> <product.app or ""> <simulator-udid> [device-name]
	set -uo pipefail

	container=$1 scheme=$2 product=$3 udid=$4 device=${5:-$4}
	case $container in
		*.xcworkspace) container_flag=-workspace ;;
		*) container_flag=-project ;;
	esac
	destination="platform=iOS Simulator,id=$udid"

	notify() { printf '\033]9;%s\007' "$1"; }
	step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }
	fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1"; notify "$1"; exit 1; }

	step "Building $scheme for $device"
	if command -v xcbeautify >/dev/null 2>&1; then
		xcodebuild "$container_flag" "$container" -scheme "$scheme" -destination "$destination" build | xcbeautify
	else
		printf 'Only warnings and errors are shown; install xcbeautify to follow the build.\n'
		xcodebuild -quiet "$container_flag" "$container" -scheme "$scheme" -destination "$destination" build
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
	xcrun simctl bootstatus "$udid" -b >/dev/null || fail "Could not boot $device"
	xcrun simctl install "$udid" "$app" || fail "Could not install $product on $device"

	step "Launching $bundle_id (Ctrl-C stops it)"
	trap 'xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1; step "Stopped"; exit 130' INT
	notify "$scheme is running on $device"
	xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id"
	status=$?
	trap - INT
	step "$scheme exited ($status)"
	"""#
}
