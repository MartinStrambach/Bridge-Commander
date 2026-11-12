import AppKit

/// The system share picker for some text, under a view, reporting when it closes.
@MainActor
public final class SharePicker: NSObject, @MainActor NSSharingServicePickerDelegate {
	private let ended: @MainActor () -> Void
	/// The picker holds its delegate weakly; this one lets go of itself once the picker closes.
	private var keptAlive: SharePicker?

	private init(ended: @escaping @MainActor () -> Void) {
		self.ended = ended
	}

	public static func show(_ text: String, below view: NSView, ended: @escaping @MainActor () -> Void) {
		let delegate = SharePicker(ended: ended)
		delegate.keptAlive = delegate
		let picker = NSSharingServicePicker(items: [text])
		picker.delegate = delegate
		picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
	}

	/// Called with a service when one is chosen and with `nil` when the picker is dismissed.
	public func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
		ended()
		keptAlive = nil
	}
}
