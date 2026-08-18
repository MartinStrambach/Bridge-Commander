import SwiftUI

/// An indicator dot showing terminal session state, 6pt by default.
/// Green for active/launching, amber pulsing for waitingForInput, clear otherwise.
public struct TerminalStatusDotView: View {
	public let status: TerminalSessionStatus?
	public let size: CGFloat

	public init(status: TerminalSessionStatus?, size: CGFloat = 6) {
		self.status = status
		self.size = size
	}

	public var body: some View {
		switch status {
		case .active,
		     .launching:
			Circle()
				.fill(Color.green)
				.frame(width: size, height: size)

		case .waitingForInput:
			PulsingAmberDot(size: size)

		case .failed,
		     nil:
			Circle()
				.fill(Color.clear)
				.frame(width: size, height: size)
		}
	}
}

private struct PulsingAmberDot: View {
	let size: CGFloat

	@State private var pulsing = false

	var body: some View {
		Circle()
			.fill(Color.orange)
			.frame(width: size, height: size)
			.scaleEffect(pulsing ? 1.4 : 1.0)
			.onAppear {
				withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
					pulsing = true
				}
			}
	}
}
