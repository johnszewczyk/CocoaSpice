import AppKit

@MainActor
final class LibraryScanLiveLogWindow {
    private let window: NSWindow
    private let textView = NSTextView()
    private let rootName: String
    private var issueCount = 0
    private var renderedIssueCount = 0

    init(root: LibraryScanRoot, pastIssues: [String] = []) {
        rootName = root.standardizedURL.lastPathComponent

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .secondaryLabelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.center()
        window.isReleasedWhenClosed = false

        append(contentsOf: pastIssues, scrollToEnd: false)
        if pastIssues.isEmpty {
            updateTitle(status: root.lastScanCompletedAt == nil ? "Waiting" : "No issues")
        } else {
            updateTitle(status: "(pastIssues.count) issue\(pastIssues.count == 1 ? "" : "s")")
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func update(current: Int, total: Int, detail: String) {
        updateTitle(status: "Scanning \(current) / \(max(total, 0)) • \(issueCount) issue\(issueCount == 1 ? "" : "s")")
    }

    func finish(successful: Int, failed: Int, unsupported: Int) {
        updateTitle(status: "Finished • \(successful) successful • \(failed) failed • \(unsupported) unsupported")
    }

    func append(_ issue: String) {
        append(contentsOf: [issue], scrollToEnd: true)
        updateTitle(status: "Scanning • \(issueCount) issue\(issueCount == 1 ? "" : "s")")
    }

    func close() {
        window.close()
    }

    private func updateTitle(status: String) {
        window.title = "Scan Log — \(rootName) • \(status)"
    }

    private func append(contentsOf issues: [String], scrollToEnd: Bool) {
        guard !issues.isEmpty else { return }
        issueCount += issues.count
        let available = max(0, LibraryScanLogStore.maximumRenderedIssues - renderedIssueCount)
        let renderedIssues = Array(issues.prefix(available))
        renderedIssueCount += renderedIssues.count
        guard !renderedIssues.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textView.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        textView.textStorage?.append(NSAttributedString(
            string: renderedIssues.joined(separator: "\n").appending("\n"),
            attributes: attributes
        ))
        if scrollToEnd { textView.scrollToEndOfDocument(nil) }
    }
}
