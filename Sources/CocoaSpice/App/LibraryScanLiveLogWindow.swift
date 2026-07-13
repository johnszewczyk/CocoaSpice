import AppKit

@MainActor
final class LibraryScanLiveLogWindow {
    private let window: NSWindow
    private let pathLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "Waiting to scan")
    private let currentFileLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private var issueCount = 0

    init(root: LibraryScanRoot, pastIssues: [String] = []) {
        pathLabel.stringValue = root.path
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pathLabel.textColor = .secondaryLabelColor

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.controlSize = .small
        progressIndicator.style = .bar

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.alignment = .right
        progressLabel.setContentHuggingPriority(.required, for: .horizontal)

        currentFileLabel.lineBreakMode = .byTruncatingMiddle
        currentFileLabel.font = .systemFont(ofSize: 12)
        currentFileLabel.textColor = .labelColor

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .textColor
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

        let progressRow = NSStackView(views: [progressIndicator, progressLabel])
        progressRow.orientation = .horizontal
        progressRow.spacing = 10
        progressIndicator.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [pathLabel, progressRow, currentFileLabel, detailLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 7
        header.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        let divider = NSBox()
        divider.boxType = .separator
        let content = NSStackView(views: [header, divider, scrollView])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 0
        content.setHuggingPriority(.defaultLow, for: .vertical)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scan Log — \(root.standardizedURL.lastPathComponent)"
        window.contentView = content
        window.center()
        window.isReleasedWhenClosed = false

        pastIssues.forEach(append)
        if !pastIssues.isEmpty {
            detailLabel.stringValue = "Last scan completed with \(pastIssues.count) issue\(pastIssues.count == 1 ? "" : "s")"
        } else if root.lastScanCompletedAt != nil {
            detailLabel.stringValue = "Last scan completed without issues"
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func update(current: Int, total: Int, detail: String) {
        let safeTotal = max(total, 0)
        progressIndicator.doubleValue = safeTotal > 0 ? Double(current) / Double(safeTotal) : 0
        progressLabel.stringValue = "\(current) / \(safeTotal) files"
        currentFileLabel.stringValue = detail
        detailLabel.stringValue = "Scanning • \(issueCount) issue\(issueCount == 1 ? "" : "s")"
    }

    func finish(successful: Int, failed: Int, unsupported: Int) {
        progressIndicator.doubleValue = 1
        currentFileLabel.stringValue = ""
        detailLabel.stringValue = "Finished • \(successful) successful • \(failed) failed • \(unsupported) unsupported"
    }

    func append(_ issue: String) {
        issueCount += 1
        textView.string += issue.appending("\n")
        textView.scrollToEndOfDocument(nil)
    }

    func close() {
        window.close()
    }
}
