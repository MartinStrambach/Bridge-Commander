import AppUI
import ComposableArchitecture
import SwiftUI

/// The simulator beside the terminal: a device menu, its controls, and its live screen.
public struct SimulatorPaneView: View {
	let store: StoreOf<SimulatorPaneReducer>
	/// The space the panel offers, from which the pane takes a width that fits the device's
	/// screen at the available height.
	let availableSize: CGSize
	/// The repository whose terminal the pane is beside, which its close button hides it for.
	let repositoryPath: String

	public init(store: StoreOf<SimulatorPaneReducer>, availableSize: CGSize, repositoryPath: String) {
		self.store = store
		self.availableSize = availableSize
		self.repositoryPath = repositoryPath
	}

	private static let headerHeight: CGFloat = 36
	private static let screenPadding: CGFloat = 12

	/// Wide enough for the device's screen at the height left under the header, within limits that
	/// keep the terminal usable.
	private var paneWidth: CGFloat {
		let aspect: CGFloat = if let size = store.selectedDevice?.displayedPixelSize, size.height > 0 {
			size.width / size.height
		}
		else {
			0.46
		}
		let screenHeight = max(availableSize.height - Self.headerHeight - Self.screenPadding * 2, 100)
		let fitting = screenHeight * aspect + Self.screenPadding * 2
		return min(max(fitting, 280), max(availableSize.width * 0.5, 280))
	}

	public var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			if !store.isClaudeCodeConnected {
				connectBanner
				Divider()
			}
			if let message = store.errorMessage ?? store.loadErrorMessage {
				errorBanner(message)
				Divider()
			}
			content
				// Over the screen rather than above it, so saving does not shrink the device.
				.overlay(alignment: .top) {
					if let url = store.savedScreenshotURL {
						screenshotBanner(url)
							.transition(.move(edge: .top).combined(with: .opacity))
					}
				}
				.animation(.easeOut(duration: 0.2), value: store.savedScreenshotURL)
		}
		.frame(width: paneWidth)
		.background(Color(NSColor.underPageBackgroundColor))
		// Restarted with the repository, so switching between two repositories that both show the
		// pane switches to the other's device.
		.task(id: repositoryPath) {
			await store.send(.task(repositoryPath: repositoryPath)).finish()
		}
	}

	// MARK: - Header

	private var header: some View {
		HStack(spacing: 6) {
			deviceMenu

			Spacer(minLength: 4)

			if let device = store.selectedDevice {
				if store.transitioningDeviceId == device.id || device.state == .booting {
					ProgressView()
						.controlSize(.small)
				}
				else if device.isBooted {
					if store.isSavingScreenshot {
						ProgressView()
							.controlSize(.small)
							.frame(width: 22, height: 22)
					}
					else {
						iconButton("camera", help: "Save Screenshot") { store.send(.screenshotButtonTapped) }
					}
					iconButton("rotate.left", help: "Rotate Left") { store.send(.rotateButtonTapped(clockwise: false)) }
					iconButton("rotate.right", help: "Rotate Right") { store.send(.rotateButtonTapped(clockwise: true)) }
					iconButton("house", help: "Home") { store.send(.hardwareButtonTapped(.home)) }
					iconButton("lock", help: "Lock") { store.send(.hardwareButtonTapped(.lock)) }
					iconButton("power", help: "Shut down \(device.name)") { store.send(.shutdownButtonTapped) }
				}
			}

			iconButton("xmark", help: "Hide Simulator") {
				store.send(.closeButtonTapped(repositoryPath: repositoryPath))
			}
		}
		.padding(.horizontal, 10)
		.frame(height: Self.headerHeight)
	}

	private var deviceMenu: some View {
		Menu {
			ForEach(store.devices) { device in
				Button {
					store.send(.deviceSelected(device.id))
				} label: {
					if device.id == store.selectedDeviceId {
						Label(menuTitle(for: device), systemImage: "checkmark")
					}
					else {
						Text(menuTitle(for: device))
					}
				}
			}
		} label: {
			Text(store.selectedDevice?.name ?? "No Simulator")
				.scaledFont(.subheadline, weight: .semibold)
				.lineLimit(1)
		}
		.menuStyle(.borderlessButton)
		.fixedSize()
		.labelStyle(.titleAndIcon)
		.disabled(store.devices.isEmpty)
	}

	private func menuTitle(for device: SimulatorDevice) -> String {
		let booted = device.isBooted ? " — Booted" : ""
		return "\(device.name) (\(device.runtimeName))\(booted)"
	}

	private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: systemImage)
				.scaledFont(size: 12)
				.frame(width: 22, height: 22)
				.contentShape(Rectangle())
		}
		.buttonStyle(.borderless)
		.help(help)
	}

	// MARK: - Banners

	private var connectBanner: some View {
		BannerView(
			icon: "sparkles",
			title: "Let Claude Code use this simulator",
			subtitle: "Adds the \(ClaudeCodeRegistration.serverName) MCP server to Claude Code. Restart Claude in open tabs to pick it up.",
			color: .accentColor,
			actionLabel: "Connect",
			isLoading: store.isConnectingClaudeCode,
			onAction: { store.send(.connectClaudeCodeButtonTapped) }
		)
	}

	private func screenshotBanner(_ url: URL) -> some View {
		BannerView(
			icon: "camera.fill",
			title: "Screenshot saved",
			subtitle: url.lastPathComponent,
			color: .green,
			actionLabel: "Show in Finder",
			onAction: { store.send(.showScreenshotInFinderTapped) },
			onDismiss: { store.send(.screenshotBannerDismissed) }
		)
		.background(.regularMaterial)
		.clipShape(RoundedRectangle(cornerRadius: 10))
		.shadow(color: .black.opacity(0.2), radius: 8, y: 2)
		.padding(8)
	}

	private func errorBanner(_ message: String) -> some View {
		BannerView(
			icon: "exclamationmark.triangle.fill",
			title: message,
			color: .orange,
			onDismiss: store.errorMessage == nil ? nil : { store.send(.errorDismissed) }
		)
	}

	// MARK: - Screen

	@ViewBuilder
	private var content: some View {
		if let device = store.selectedDevice {
			if device.isBooted {
				SimulatorScreen(deviceId: device.id, screenPixelSize: device.screenPixelSize)
					.aspectRatio(device.displayedPixelSize, contentMode: .fit)
					.padding(Self.screenPadding)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else {
				placeholder {
					Image(systemName: "iphone")
						.scaledFont(size: 40)
						.foregroundStyle(.tertiary)
					Text(device.state == .booting ? "Booting \(device.name)…" : "\(device.name) is \(device.state.label.lowercased())")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
					if device.state == .shutdown {
						Button("Boot") { store.send(.bootButtonTapped) }
							.buttonStyle(.scaledBorderedProminent)
							.disabled(store.transitioningDeviceId != nil)
					}
				}
			}
		}
		else {
			placeholder {
				if store.hasLoadedDevices {
					Text("No iOS simulators found. Install an iOS runtime in Xcode ▸ Settings ▸ Components.")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}
				else {
					ProgressView()
				}
			}
		}
	}

	private func placeholder(@ViewBuilder _ content: () -> some View) -> some View {
		VStack(spacing: 12) {
			content()
		}
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
