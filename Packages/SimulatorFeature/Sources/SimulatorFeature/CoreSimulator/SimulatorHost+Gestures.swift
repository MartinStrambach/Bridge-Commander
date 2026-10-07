import CoreGraphics
import Foundation

/// Two finger positions, in screen points or normalized, depending on the call.
public struct FingerPair: Equatable, Sendable {
	public var first: CGPoint
	public var second: CGPoint

	public init(_ first: CGPoint, _ second: CGPoint) {
		self.first = first
		self.second = second
	}
}

extension SimulatorHost {
	// MARK: - Accessibility

	/// The frontmost app's accessibility tree.
	public func accessibilityTree(device: SimulatorDevice) async throws -> SimulatorAccessibilityNode {
		try await SimulatorAccessibility.shared.frontmostTree(device: ObjectBox(object: simDevice(udid: device.id)))
	}

	/// The element at a point in screen points, if any. Hit-testing takes the point on the portrait
	/// panel, though the frames it returns are in the interface's space like the tree's.
	public func accessibilityElement(device: SimulatorDevice, at point: CGPoint) async throws -> SimulatorAccessibilityNode? {
		try await SimulatorAccessibility.shared.element(at: device.nativePoint(point), device: ObjectBox(object: simDevice(udid: device.id)))
	}

	// MARK: - Multi-touch

	/// One phase of a two-finger contact at normalized points, for the pane's live gestures.
	public func twoFingerTouch(udid: String, fingers: FingerPair, phase: Int) async throws {
		guard let phase = SimulatorTouchPhase(rawValue: UInt64(phase)) else {
			return
		}
		try await hidConnection(udid: udid).touch(fingers.first, fingers.second, phase: phase)
	}

	/// Two fingers moving together from `start` to `end` (points), interpolated linearly: a pinch,
	/// a rotation or a two-finger drag depending on the positions. Points off the screen are
	/// clamped to its edge.
	public func twoFingerGesture(
		device: SimulatorDevice,
		from start: FingerPair,
		to end: FingerPair,
		duration: Duration = .milliseconds(400)
	) async throws {
		let connection = try await hidConnection(udid: device.id)
		func normalized(_ point: CGPoint) -> CGPoint {
			device.normalizedPoint(clamping: point)
		}

		let interval = Duration.milliseconds(16)
		let steps = max(2, Int(duration / interval))
		connection.touch(normalized(start.first), normalized(start.second), phase: .began)
		for step in 1...steps {
			try await Task.sleep(for: interval)
			let progress = CGFloat(step) / CGFloat(steps)
			let fingers = Self.interpolate(start, end, progress)
			connection.touch(normalized(fingers.first), normalized(fingers.second), phase: .moved)
		}
		connection.touch(normalized(end.first), normalized(end.second), phase: .ended)
		try await drain()
	}

	static func interpolate(_ start: FingerPair, _ end: FingerPair, _ progress: CGFloat) -> FingerPair {
		func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
			CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
		}
		return FingerPair(mix(start.first, end.first), mix(start.second, end.second))
	}

	/// Finger positions for a pinch about `center` (points) that scales by `scale` and turns by
	/// `rotationDegrees`, clockwise as seen on screen. Spreading from 60 pt apart zooms in; closing
	/// to 60 pt apart zooms out, so either direction starts and ends at a comfortable spacing.
	public static func pinchFingers(center: CGPoint, scale: Double, rotationDegrees: Double) -> (start: FingerPair, end: FingerPair) {
		let scale = max(scale, 0.05)
		let near: Double = 30
		let startRadius = scale >= 1 ? near : min(near / scale, 220)
		let endRadius = startRadius * scale
		let endAngle = rotationDegrees * .pi / 180

		func fingers(radius: Double, angle: Double) -> FingerPair {
			let dx = radius * cos(angle)
			let dy = radius * sin(angle)
			return FingerPair(
				CGPoint(x: center.x - dx, y: center.y - dy),
				CGPoint(x: center.x + dx, y: center.y + dy)
			)
		}
		return (fingers(radius: startRadius, angle: 0), fingers(radius: endRadius, angle: endAngle))
	}
}
