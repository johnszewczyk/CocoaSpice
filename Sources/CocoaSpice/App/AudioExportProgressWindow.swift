import AppKit
import Foundation

@MainActor
final class AudioExportProgressWindowController: NSWindowController {
    private let titleField = NSTextField(labelWithString: "")
    private let filenameField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private let currentFileProgressIndicator = NSProgressIndicator()
    private let batchProgressIndicator = NSProgressIndicator()
    private let pathField = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let onCancel: @MainActor () -> Void
    private var autoCloseTask: Task<Void, Never>?
    private var exportIsActive = false

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel

        let contentRect = NSRect(x: 0, y: 0, width: 560, height: 290)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Export AAC Audio"
        window.isReleasedWhenClosed = false
        window.center()

        let contentView = NSView(frame: contentRect)
        window.contentView = contentView
        super.init(window: window)

        titleField.font = .systemFont(ofSize: 15, weight: .semibold)
        titleField.translatesAutoresizingMaskIntoConstraints = false

        filenameField.font = .systemFont(ofSize: 13, weight: .medium)
        filenameField.lineBreakMode = .byTruncatingMiddle
        filenameField.cell?.wraps = false
        filenameField.cell?.isScrollable = true
        filenameField.translatesAutoresizingMaskIntoConstraints = false

        countField.font = .systemFont(ofSize: 12)
        countField.textColor = .secondaryLabelColor
        countField.alignment = .right
        countField.translatesAutoresizingMaskIntoConstraints = false

        configure(progressIndicator: currentFileProgressIndicator)
        configure(progressIndicator: batchProgressIndicator)

        pathField.font = .systemFont(ofSize: 11)
        pathField.textColor = .secondaryLabelColor
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.cell?.wraps = false
        pathField.cell?.isScrollable = true
        pathField.translatesAutoresizingMaskIntoConstraints = false

        let currentFileLabel = NSTextField(labelWithString: "Current File")
        currentFileLabel.font = .systemFont(ofSize: 11, weight: .medium)
        currentFileLabel.textColor = .secondaryLabelColor
        currentFileLabel.translatesAutoresizingMaskIntoConstraints = false

        let batchLabel = NSTextField(labelWithString: "Overall Progress")
        batchLabel.font = .systemFont(ofSize: 11, weight: .medium)
        batchLabel.textColor = .secondaryLabelColor
        batchLabel.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelExport)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [
            titleField,
            filenameField,
            countField,
            currentFileLabel,
            currentFileProgressIndicator,
            batchLabel,
            batchProgressIndicator,
            pathField,
            cancelButton
        ] {
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            titleField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            currentFileLabel.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 20),
            currentFileLabel.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            countField.centerYAnchor.constraint(equalTo: currentFileLabel.centerYAnchor),
            countField.leadingAnchor.constraint(greaterThanOrEqualTo: currentFileLabel.trailingAnchor, constant: 12),
            countField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),

            filenameField.topAnchor.constraint(equalTo: currentFileLabel.bottomAnchor, constant: 5),
            filenameField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            filenameField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),

            currentFileProgressIndicator.topAnchor.constraint(equalTo: filenameField.bottomAnchor, constant: 9),
            currentFileProgressIndicator.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            currentFileProgressIndicator.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),

            batchLabel.topAnchor.constraint(equalTo: currentFileProgressIndicator.bottomAnchor, constant: 17),
            batchLabel.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            batchProgressIndicator.topAnchor.constraint(equalTo: batchLabel.bottomAnchor, constant: 6),
            batchProgressIndicator.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            batchProgressIndicator.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),

            pathField.topAnchor.constraint(equalTo: batchProgressIndicator.bottomAnchor, constant: 15),
            pathField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            pathField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),

            cancelButton.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 17),
            cancelButton.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(snapshot: AudioExportProgressSnapshot) {
        autoCloseTask?.cancel()
        apply(snapshot: snapshot)
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    func apply(snapshot: AudioExportProgressSnapshot) {
        autoCloseTask?.cancel()
        titleField.stringValue = snapshot.title
        pathField.stringValue = snapshot.outputDirectoryPath
        filenameField.stringValue = snapshot.currentFileName ?? fallbackFilename(for: snapshot.phase)

        if snapshot.totalFiles > 0 {
            countField.stringValue = "\(snapshot.completedFiles) completed  •  \(snapshot.remainingFiles) remaining"
        } else {
            countField.stringValue = ""
        }

        updateCurrentFileProgress(snapshot.currentFileProgress, phase: snapshot.phase)
        setDeterminateProgress(batchProgressIndicator, value: snapshot.batchProgress)

        switch snapshot.phase {
        case .preparing, .exporting:
            exportIsActive = true
            cancelButton.isEnabled = true
            cancelButton.title = "Cancel"
        case .completed, .cancelled, .failed:
            exportIsActive = false
            cancelButton.isEnabled = true
            cancelButton.title = "Close"
        }
    }

    func closeAutomatically(after delayNanoseconds: UInt64 = 1_200_000_000) {
        autoCloseTask?.cancel()
        autoCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func configure(progressIndicator: NSProgressIndicator) {
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.controlSize = .regular
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateCurrentFileProgress(_ progress: Double?, phase: AudioExportProgressSnapshot.Phase) {
        if let progress {
            setDeterminateProgress(currentFileProgressIndicator, value: progress)
            return
        }

        switch phase {
        case .preparing, .exporting:
            currentFileProgressIndicator.doubleValue = 0
            currentFileProgressIndicator.isIndeterminate = true
            currentFileProgressIndicator.startAnimation(nil)
        case .completed:
            setDeterminateProgress(currentFileProgressIndicator, value: 1)
        case .cancelled, .failed:
            currentFileProgressIndicator.stopAnimation(nil)
            currentFileProgressIndicator.isIndeterminate = false
        }
    }

    private func setDeterminateProgress(_ indicator: NSProgressIndicator, value: Double) {
        if indicator.isIndeterminate {
            indicator.stopAnimation(nil)
            indicator.isIndeterminate = false
        }
        indicator.doubleValue = min(max(value, 0), 1)
    }

    private func fallbackFilename(for phase: AudioExportProgressSnapshot.Phase) -> String {
        switch phase {
        case .preparing: "Reading track metadata…"
        case .completed: "All files exported"
        case .cancelled: "Export cancelled"
        case .failed: "Export failed"
        case .exporting: "Preparing current file…"
        }
    }

    @objc private func cancelExport() {
        guard exportIsActive else {
            close()
            return
        }
        cancelButton.isEnabled = false
        cancelButton.title = "Cancelling…"
        onCancel()
    }
}
