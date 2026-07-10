import AppKit
import Foundation

@MainActor
final class AudioExportProgressWindowController: NSWindowController {
    private let progressIndicator = NSProgressIndicator()
    private let pathField = NSTextField(labelWithString: "")
    private let filenameField = NSTextField(labelWithString: "")
    private var autoCloseTask: Task<Void, Never>?

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 640, height: 240)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AAC Export"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let contentView = NSView(frame: contentRect)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.controlSize = .regular
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        pathField.font = .systemFont(ofSize: 12)
        pathField.textColor = .secondaryLabelColor
        pathField.translatesAutoresizingMaskIntoConstraints = false
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.cell?.wraps = false
        pathField.cell?.isScrollable = true

        filenameField.font = .systemFont(ofSize: 13, weight: .semibold)
        filenameField.translatesAutoresizingMaskIntoConstraints = false
        filenameField.lineBreakMode = .byTruncatingMiddle
        filenameField.cell?.wraps = false
        filenameField.cell?.isScrollable = true

        contentView.addSubview(progressIndicator)
        contentView.addSubview(pathField)
        contentView.addSubview(filenameField)

        NSLayoutConstraint.activate([
            progressIndicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            progressIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            progressIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            pathField.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 22),
            pathField.leadingAnchor.constraint(equalTo: progressIndicator.leadingAnchor),
            pathField.trailingAnchor.constraint(equalTo: progressIndicator.trailingAnchor),
            filenameField.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 10),
            filenameField.leadingAnchor.constraint(equalTo: progressIndicator.leadingAnchor),
            filenameField.trailingAnchor.constraint(equalTo: progressIndicator.trailingAnchor)
        ])

        super.init(window: window)
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
        let url = URL(fileURLWithPath: snapshot.detail)
        let hasExtension = !url.pathExtension.isEmpty
        if hasExtension {
            pathField.stringValue = url.deletingLastPathComponent().path
            filenameField.stringValue = url.lastPathComponent
        } else {
            pathField.stringValue = snapshot.detail
            filenameField.stringValue = snapshot.title
        }

        if let progress = snapshot.progress {
            if progressIndicator.isIndeterminate {
                progressIndicator.stopAnimation(nil)
                progressIndicator.isIndeterminate = false
            }
            progressIndicator.doubleValue = min(max(progress, 0), 1)
        } else {
            progressIndicator.doubleValue = 0
            if !progressIndicator.isIndeterminate {
                progressIndicator.isIndeterminate = true
            }
            progressIndicator.startAnimation(nil)
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
}
