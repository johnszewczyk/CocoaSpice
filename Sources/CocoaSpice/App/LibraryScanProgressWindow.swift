import AppKit

@MainActor
final class LibraryScanProgressWindowController {
    private let window: NSWindow
    private let textView: NSTextView
    private let onCancel: () -> Void
    private let cancelTarget: ActionTarget

    init(title: String, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 440))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView

        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        let cancelAction = onCancel
        cancelTarget = ActionTarget { cancelAction() }
        cancelButton.target = cancelTarget
        cancelButton.action = #selector(ActionTarget.invoke)

        let stack = NSStackView(views: [scrollView, cancelButton])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        cancelButton.setContentHuggingPriority(.required, for: .vertical)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = stack
        window.center()
        window.isReleasedWhenClosed = false
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func append(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        textView.string += "[\(formatter.string(from: Date()))] \(message)\n"
        textView.scrollToEndOfDocument(nil)
    }

    func close() {
        window.close()
    }
}

private final class ActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}
