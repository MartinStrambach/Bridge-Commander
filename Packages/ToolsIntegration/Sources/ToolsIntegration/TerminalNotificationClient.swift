import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import Synchronization
import UserNotifications

// MARK: - Terminal Notification Client

/// What a built-in terminal tab shows in Notification Center.
public struct TerminalNotificationContent: Equatable, Sendable {
	public var sessionId: UUID
	public var title: String
	public var subtitle: String?
	public var body: String

	public init(sessionId: UUID, title: String, subtitle: String? = nil, body: String) {
		self.sessionId = sessionId
		self.title = title
		self.subtitle = subtitle
		self.body = body
	}
}

/// Posts a system notification for a built-in terminal tab — Claude Code waiting for the user, or
/// any program asking for one with OSC 9 / OSC 777 — and reports which tab's notification was
/// clicked.
///
/// A notification's identifier is its terminal session's id, so a second post for the same tab
/// replaces the first rather than stacking, and a click can name the tab to open. A tab's
/// notifications are spaced at least `NotificationThrottle` interval apart: one posted sooner
/// waits, and only the latest of those waiting is shown.
@DependencyClient
public struct TerminalNotificationClient: Sendable {
	/// Asks for permission on first use; posts nothing when it is refused. Returns once the
	/// notification is shown or dropped, which a throttled one may take a moment.
	public var post: @Sendable (_ content: TerminalNotificationContent) async -> Void
	/// Withdraws the tab's notification, delivered, pending or still waiting out the throttle.
	public var remove: @Sendable (_ sessionId: UUID) async -> Void
	/// The session ids of clicked notifications. One subscriber at a time: a new call finishes
	/// the stream handed out before it.
	public var taps: @Sendable () -> AsyncStream<UUID> = { AsyncStream { $0.finish() } }
	public var isAppActive: @Sendable () async -> Bool = { false }
	/// Brings the app forward, restoring a minimized window.
	public var activateApp: @Sendable () async -> Void
}

extension TerminalNotificationClient: DependencyKey {
	/// Two seconds lets a program answer a dialog and finish the turn without a second alert, and
	/// is still soon enough that the news it carries is not stale.
	private static let throttle = Mutex(NotificationThrottle(interval: 2))

	public static let liveValue = TerminalNotificationClient(
		post: { notification in
			let id = notification.sessionId
			let (ticket, delay) = throttle.withLock { $0.schedule(id, at: Date()) }
			if delay > 0 {
				try? await Task.sleep(for: .seconds(delay))
			}
			guard throttle.withLock({ $0.claim(id, ticket: ticket, at: Date()) }) else {
				return
			}

			let center = UNUserNotificationCenter.current()
			TerminalNotificationDelegate.install()
			guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
				return
			}

			let content = UNMutableNotificationContent()
			content.title = notification.title
			if let subtitle = notification.subtitle {
				content.subtitle = subtitle
			}
			content.body = notification.body
			content.sound = .default
			let request = UNNotificationRequest(
				identifier: notification.sessionId.uuidString,
				content: content,
				trigger: nil
			)
			try? await center.add(request)
		},
		remove: { sessionId in
			throttle.withLock { $0.cancel(sessionId) }
			let center = UNUserNotificationCenter.current()
			center.removeDeliveredNotifications(withIdentifiers: [sessionId.uuidString])
			center.removePendingNotificationRequests(withIdentifiers: [sessionId.uuidString])
		},
		taps: {
			TerminalNotificationDelegate.install().taps()
		},
		isAppActive: {
			await MainActor.run { NSApp.isActive }
		},
		activateApp: {
			await MainActor.run {
				for window in NSApp.windows where window.isMiniaturized {
					window.deminiaturize(nil)
				}
				NSApp.activate()
			}
		}
	)
}

extension TerminalNotificationClient: TestDependencyKey {
	public static let testValue = TerminalNotificationClient()
}

// MARK: - Delegate

/// Receives the clicks. It has to be the notification center's delegate before a click
/// arrives, so both posting and subscribing install it.
private final nonisolated class TerminalNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
	/// Lazily initialized exactly once, which is what makes `install()` safe to call from anywhere.
	private static let shared: TerminalNotificationDelegate = {
		let delegate = TerminalNotificationDelegate()
		UNUserNotificationCenter.current().delegate = delegate
		return delegate
	}()

	private let continuation = Mutex<AsyncStream<UUID>.Continuation?>(nil)

	@discardableResult
	static func install() -> TerminalNotificationDelegate {
		shared
	}

	func taps() -> AsyncStream<UUID> {
		let (stream, newContinuation) = AsyncStream<UUID>.makeStream(bufferingPolicy: .bufferingNewest(1))
		continuation.withLock { current in
			current?.finish()
			current = newContinuation
		}
		return stream
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse
	) async {
		guard
			response.actionIdentifier == UNNotificationDefaultActionIdentifier,
			let sessionId = UUID(uuidString: response.notification.request.identifier)
		else {
			return
		}

		continuation.withLock { _ = $0?.yield(sessionId) }
	}

	/// Shown even while the app is frontmost: the reducer only posts for a tab the user is not
	/// looking at, and that tab may well be hidden behind another one in this very window.
	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification
	) async -> UNNotificationPresentationOptions {
		[.banner, .list, .sound]
	}
}
