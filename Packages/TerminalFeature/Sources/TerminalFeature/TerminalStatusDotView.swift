import SwiftUI

/// An indicator dot showing terminal session state, 6pt by default.
/// Green for active/launching, amber pulsing for waitingForInput, clear otherwise.
public struct TerminalStatusDotView: View {
	public let status: TerminalSessionStatus?
	public let size: CGFloat
	/// `false` leaves a running terminal's green dot out (its space stays), for lists where every
	/// row has a terminal and only the ones needing attention should stand out.
	public let showsActive: Bool

	public init(status: TerminalSessionStatus?, size: CGFloat = 6, showsActive: Bool = true) {
		self.status = status
		self.size = size
		self.showsActive = showsActive
	}

	public var body: some View {
		switch status {
		case .active,
		     .launching:
			Circle()
				.fill(showsActive ? Color.green : Color.clear)
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
