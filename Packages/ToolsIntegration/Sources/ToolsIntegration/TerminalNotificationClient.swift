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
/// replaces the first rather than stacking, and a click can name the tab to open.
@DependencyClient
public struct TerminalNotificationClient: Sendable {
	/// Asks for permission on first use; posts nothing when it is refused.
	public var post: @Sendable (_ content: TerminalNotificationContent) async -> Void
	/// Withdraws the tab's notification, delivered or not.
	public var remove: @Sendable (_ sessionId: UUID) async -> Void
	/// The session ids of clicked notifications. One subscriber at a time: a new call finishes
	/// the stream handed out before it.
	public var taps: @Sendable () -> AsyncStream<UUID> = { AsyncStream { $0.finish() } }
	public var isAppActive: @Sendable () async -> Bool = { false }
	/// Brings the app forward, restoring a minimized window.
	public var activateApp: @Sendable () async -> Void
}

extension TerminalNotificationClient: DependencyKey {
	public static let liveValue = TerminalNotificationClient(
		post: { notification in
			let center = UNUserNotificationCenter.current()
			TerminalNotificationDelegate.shared.install()
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
			let center = UNUserNotificationCenter.current()
			center.removeDeliveredNotifications(withIdentifiers: [sessionId.uuidString])
			center.removePendingNotificationRequests(withIdentifiers: [sessionId.uuidString])
		},
		taps: {
			TerminalNotificationDelegate.shared.install()
			return TerminalNotificationDelegate.shared.taps()
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
	static let shared = TerminalNotificationDelegate()

	private let continuation = Mutex<AsyncStream<UUID>.Continuation?>(nil)
	private let isInstalled = Mutex(false)

	func install() {
		let shouldInstall = isInstalled.withLock { installed in
			defer { installed = true }
			return !installed
		}
		if shouldInstall {
			UNUserNotificationCenter.current().delegate = self
		}
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
