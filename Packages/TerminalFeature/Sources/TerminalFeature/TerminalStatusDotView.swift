// BridgeCommander/Components/TerminalStatusDotView.swift
import SwiftUI

/// A 6pt indicator dot showing terminal session state.
/// Green for active/launching, amber pulsing for waitingForInput, clear otherwise.
public struct TerminalStatusDotView: View {
	public let status: TerminalSessionStatus?

	public init(status: TerminalSessionStatus?) {
		self.status = status
	}

	public var body: some View {
		switch status {
		case .active,
		     .launching:
			Circle()
				.fill(Color.green)
				.frame(width: 6, height: 6)

		case .waitingForInput:
			PulsingAmberDot()

		case .failed,
		     nil:
			Circle()
				.fill(Color.clear)
				.frame(width: 6, height: 6)
		}
	}
}

private struct PulsingAmberDot: View {
	@State private var pulsing = false

	var body: some View {
		Circle()
			.fill(Color.orange)
			.frame(width: 6, height: 6)
			.scaleEffect(pulsing ? 1.4 : 1.0)
			.onAppear {
				withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
					pulsing = true
				}
			}
	}
}
