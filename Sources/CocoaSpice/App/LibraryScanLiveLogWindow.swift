import AppKit

@MainActor
final class LibraryScanLiveLogWindow {
    private let window: NSWindow
    private let textView = NSTextView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let rootName: String
    private var issueCount = 0
    private var renderedIssueCount = 0

    init(root: LibraryScanRoot, pastIssues: [String] = [], summary: String? = nil) {
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

        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1
        summaryLabel.stringValue = summary ?? Self.defaultSummary(for: root, issueCount: pastIssues.count)

        let content = NSStackView()
        content.orientation = .vertical
        content.spacing = 0
        content.addArrangedSubview(summaryLabel)
        content.addArrangedSubview(scrollView)
        summaryLabel.heightAnchor.constraint(equalToConstant: 36).isActive = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = content
        window.center()
        window.isReleasedWhenClosed = false

        append(contentsOf: pastIssues, scrollToEnd: false)
        updateSummary(summaryLabel.stringValue)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func update(current: Int, total: Int, detail: String) {
        updateSummary("\(detail) • \(current) / \(max(total, 0)) • \(issueCount) issue\(issueCount == 1 ? "" : "s")")
    }

    func finish(successful: Int, failed: Int, unsupported: Int) {
        updateSummary("Finished • \(successful) successful • \(failed) failed • \(unsupported) unsupported")
    }

    func append(_ issue: String) {
        append(contentsOf: [issue], scrollToEnd: true)
        updateSummary("Scanning • \(issueCount) issue\(issueCount == 1 ? "" : "s")")
    }

    func append(_ issues: [String]) {
        append(contentsOf: issues, scrollToEnd: true)
        updateSummary("Scanning • \(issueCount) issue\(issueCount == 1 ? "" : "s")")
    }

    func close() {
        window.close()
    }

    private func updateSummary(_ summary: String) {
        summaryLabel.stringValue = summary
        window.title = "Scan Log — \(rootName)"
    }

    private static func defaultSummary(for root: LibraryScanRoot, issueCount: Int) -> String {
        guard let completedAt = root.lastScanCompletedAt else {
            return "Waiting for first scan"
        }
        let completed = DateFormatter.localizedString(from: completedAt, dateStyle: .medium, timeStyle: .short)
        let duration: String
        if let startedAt = root.lastScanStartedAt {
            duration = " • \(Int(completedAt.timeIntervalSince(startedAt).rounded()))s"
        } else {
            duration = ""
        }
        return "Last scan \(completed)\(duration) • \(root.lastScanTrackCount) tracks • \(issueCount) issue\(issueCount == 1 ? "" : "s")"
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
