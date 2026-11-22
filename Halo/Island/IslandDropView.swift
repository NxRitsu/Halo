import AppKit

/// Content view of an island panel, which receives the files dragged onto the island.
///
/// The hosting view inside doesn't take drags, so they reach this view wherever the cursor is
/// over the panel. The decisions belong to the window controller.
final class IslandDropView: NSView {
    var onEnter: (NSDraggingInfo) -> NSDragOperation = { _ in [] }
    var onExit: () -> Void = {}
    var onDrop: (NSDraggingInfo) -> Bool = { _ in false }
    var onEnd: () -> Void = {}

    private var operation: NSDragOperation = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        operation = onEnter(sender)
        return operation
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        operation
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        operation = []
        onExit()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !operation.isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDrop(sender)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        operation = []
        onEnd()
    }
}
