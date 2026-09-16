import SwiftUI
import UniformTypeIdentifiers

extension View {
	/// Makes a view one item of a row that reorders *while* the drag is in flight: the moment the
	/// pointer carrying another item enters this one, the dragged item takes this one's place and
	/// the row animates around it, the way browser tabs behave. Release just ends the drag; the
	/// order is already what the user sees. Contrast `reorderable`, which moves nothing until the
	/// drop lands — right for the sidebar, where sections under a `List` cannot slide.
	///
	/// The item being dragged is tracked in `draggedId`, shared by every item of the row, because
	/// a drop delegate's `dropEntered` runs before the pasteboard payload can be read — and reading
	/// it is asynchronous anyway. The `NSItemProvider` still carries the id as `public.text`: an
	/// undeclared type starts a drag no destination ever matches (see `reorderable`), and the
	/// declared one is what `onDrop(of:)` filters on.
	@ViewBuilder
	func liveReorderable(
		id: UUID,
		isEnabled: Bool,
		draggedId: Binding<UUID?>,
		onMove: @escaping (_ dragged: UUID, _ target: UUID) -> Void
	) -> some View {
		if isEnabled {
			onDrag {
				draggedId.wrappedValue = id
				return NSItemProvider(object: id.uuidString as NSString)
			}
			.onDrop(
				of: [.text],
				delegate: LiveReorderDropDelegate(targetId: id, draggedId: draggedId, onMove: onMove)
			)
		}
		else {
			self
		}
	}
}

private struct LiveReorderDropDelegate: DropDelegate {
	let targetId: UUID
	@Binding var draggedId: UUID?
	let onMove: (UUID, UUID) -> Void

	func dropEntered(info: DropInfo) {
		// Fires once per entry, so a pointer resting over the target does not keep swapping.
		// After the move the dragged item sits under the pointer and the target has slid aside;
		// the next `dropEntered` comes only when the pointer reaches another item.
		guard let draggedId, draggedId != targetId else {
			return
		}
		onMove(draggedId, targetId)
	}

	func dropUpdated(info: DropInfo) -> DropProposal? {
		// `.move` keeps the cursor free of the green "+" badge a copy would show.
		DropProposal(operation: .move)
	}

	func performDrop(info: DropInfo) -> Bool {
		draggedId = nil
		return true
	}
}
