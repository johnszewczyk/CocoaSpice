import AppKit
import SwiftUI

struct PlaylistTableAutoSizer: NSViewRepresentable {
    @Bindable var model: PlayerViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.model = model
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: nsView)
            context.coordinator.refreshHandler()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        @Bindable var model: PlayerViewModel

        private weak var tableView: NSTableView?
        private weak var headerView: AutoSizingTableHeaderView?

        init(model: PlayerViewModel) {
            self._model = Bindable(model)
        }

        func attachIfNeeded(from view: NSView) {
            guard let tableView = findTableView(from: view) else { return }

            if self.tableView !== tableView || !(tableView.headerView is AutoSizingTableHeaderView) {
                let headerView = AutoSizingTableHeaderView(frame: tableView.headerView?.frame ?? .zero)
                headerView.autoresizingMask = [.width, .height]
                tableView.headerView = headerView
                tableView.target = self
                tableView.doubleAction = #selector(handleDoubleAction(_:))

                self.tableView = tableView
                self.headerView = headerView
            }

            refreshHandler()
        }

        func refreshHandler() {
            guard let headerView else { return }
            headerView.resizeColumn = { [weak self] column in
                self?.resizeColumn(at: column)
            }
        }

        private func resizeColumn(at columnIndex: Int) {
            guard let tableView, columnIndex >= 0, columnIndex < tableView.tableColumns.count else { return }

            let tableColumn = tableView.tableColumns[columnIndex]
            guard columnTitle(for: tableColumn) != "" else { return }

            let width = idealWidth(for: tableColumn, in: tableView)
            let minWidth = tableColumn.minWidth
            let maxWidth = tableColumn.maxWidth > 0 ? tableColumn.maxWidth : width
            tableColumn.width = min(max(width, minWidth), maxWidth)
        }

        private func idealWidth(for tableColumn: NSTableColumn, in tableView: NSTableView) -> CGFloat {
            let title = columnTitle(for: tableColumn)
            let headerWidth = textWidth(title, font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold))
            let contentWidth = switch title {
            case "#":
                widestWidth(in: model.playlist) { model.indexText(for: $0) }
            case "File":
                widestWidth(in: model.playlist) { $0.filename }
            case "Title":
                widestWidth(in: model.playlist) { model.titleText(for: $0) }
            case "Game":
                widestWidth(in: model.playlist) { model.gameText(for: $0) }
            case "Author":
                widestWidth(in: model.playlist) { model.authorText(for: $0) }
            case "System":
                widestWidth(in: model.playlist) { model.systemText(for: $0) }
            case "Path":
                widestWidth(in: model.playlist) { model.pathText(for: $0) }
            case "Length":
                widestWidth(in: model.playlist) { model.lengthText(for: $0) }
            default:
                tableColumn.width
            }

            let padding = tableView.intercellSpacing.width + 20
            return max(headerWidth, contentWidth) + padding
        }

        private func widestWidth(in tracks: [TrackItem], value: (TrackItem) -> String) -> CGFloat {
            let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            return tracks.reduce(CGFloat.zero) { currentMax, track in
                max(currentMax, textWidth(value(track), font: bodyFont))
            }
        }

        private func textWidth(_ text: String, font: NSFont) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            return (text as NSString).size(withAttributes: attributes).width
        }

        private func columnTitle(for tableColumn: NSTableColumn) -> String {
            tableColumn.headerCell.stringValue
        }

        private func findTableView(from view: NSView) -> NSTableView? {
            var root: NSView? = view
            while let current = root {
                if let tableView = findTableViewInSubtree(current) {
                    return tableView
                }
                root = current.superview
            }
            return nil
        }

        private func findTableViewInSubtree(_ view: NSView) -> NSTableView? {
            if let tableView = view as? NSTableView {
                return tableView
            }

            for subview in view.subviews {
                if let tableView = findTableViewInSubtree(subview) {
                    return tableView
                }
            }

            return nil
        }

        @objc
        private func handleDoubleAction(_ sender: NSTableView) {
            guard sender.clickedRow >= 0 else { return }
            model.playSelectedTrack()
        }
    }
}

@MainActor
private final class AutoSizingTableHeaderView: NSTableHeaderView {
    var resizeColumn: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if event.clickCount == 2, let columnIndex = dividerColumn(at: point) {
            resizeColumn?(columnIndex)
            return
        }

        super.mouseDown(with: event)
    }

    private func dividerColumn(at point: NSPoint) -> Int? {
        guard let tableView else { return nil }

        for columnIndex in 0..<tableView.numberOfColumns {
            let headerRect = self.headerRect(ofColumn: columnIndex)
            let hitRange = NSRange(location: Int(headerRect.maxX - 3), length: 7)
            if NSLocationInRange(Int(point.x), hitRange) {
                return columnIndex
            }
        }

        return nil
    }
}
