import SwiftUI
import UniformTypeIdentifiers

/// Which side of a drop target the insertion line is drawn on: `.top` for rows stacked
/// vertically, `.leading` for items laid out in a row, such as terminal tabs.
enum ReorderInsertionEdge {
	case top
	case leading
}

extension View {
	/// Makes a view both the handle for a reorder drag and the drop target that says where another
	/// item should land. The payload is a plain string identifying the item — the repository path
	/// for the sidebar's group headers — and is handed back as dropped on a target, which then
	/// decides what it means. Nothing moves until the drop lands; the terminal tabs, which reorder
	/// live under the pointer, use `liveReorderable` instead.
	///
	/// Three things here are load-bearing, each established by driving a real drag against a
	/// probe app rather than by reading docs — all of them fail *silently*, with the drag simply
	/// never landing:
	///
	/// - Drag and drop at all, rather than `ForEach.onMove`: a repository group is a `Section` of
	///   the list, and a plain macOS `List` reorders rows, never sections.
	/// - `onDrag`/`onDrop` rather than `draggable`/`dropDestination`: a section header is not a
	///   drag source for the newer API. It never even starts the drag.
	/// - A declared type — `public.text` — rather than a private one of ours. An *undeclared*
	///   identifier starts a drag that no drop destination will ever match, and declaring one
	///   would mean taking over the target's generated Info.plist. The reducer treats the dropped
	///   string as untrusted anyway: a payload that names nothing it knows is ignored, which is
	///   also what makes text dragged in from another app harmless here.
	@ViewBuilder
	func reorderable(
		payload: String,
		isEnabled: Bool,
		isTargeted: Binding<Bool>,
		insertionEdge: ReorderInsertionEdge,
		onDrop: @escaping (String) -> Void
	) -> some View {
		if isEnabled {
			onDrag { NSItemProvider(object: payload as NSString) }
				.onDrop(of: [.text], isTargeted: isTargeted) { providers in
					guard let provider = providers.first else {
						return false
					}
					// Loaded on the main actor rather than in `loadObject`'s completion handler,
					// which runs off it and so cannot be handed the callback.
					Task { @MainActor in
						let item = try? await provider.loadItem(
							forTypeIdentifier: UTType.utf8PlainText.identifier
						)
						let dragged = (item as? String)
							?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
						guard let dragged, dragged != payload else {
							return
						}
						onDrop(dragged)
					}
					return true
				}
				// An insertion line rather than a filled highlight: the view underneath already
				// has a background of its own, and the line reads as "it lands here".
				.overlay(alignment: insertionEdge == .top ? .top : .leading) {
					if isTargeted.wrappedValue {
						Rectangle()
							.fill(Color.accentColor)
							.frame(
								width: insertionEdge == .leading ? 2 : nil,
								height: insertionEdge == .top ? 2 : nil
							)
							.transition(.opacity)
					}
				}
				.animation(.easeOut(duration: 0.12), value: isTargeted.wrappedValue)
		}
		else {
			self
		}
	}
}
