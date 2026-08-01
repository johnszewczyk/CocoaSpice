import AppKit
import SwiftUI

struct PlaylistTableView: NSViewRepresentable {
    @Bindable var model: PlayerViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = PlaylistNativeTableView(frame: .zero)
        tableView.usesAlternatingRowBackgroundColors = false
        let headerView = PlaylistTableHeaderView()
        tableView.headerView = headerView
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 17
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.focusRingType = .none
        tableView.style = .fullWidth
        tableView.selectionHighlightStyle = .regular
        tableView.usesAutomaticRowHeights = false
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.registerForDraggedTypes([playlistRowDragType, databaseFileSidebarDragType, .fileURL])
        tableView.rowActivationHandler = { [weak coordinator = context.coordinator] row in
            coordinator?.activateRow(row)
        }
        tableView.returnActivationHandler = { [weak coordinator = context.coordinator] in
            coordinator?.activateSelectedRow()
        }
        tableView.rowMenuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.makeRowMenu(clickedRow: row)
        }
        headerView.headerMenuProvider = { [weak coordinator = context.coordinator] columnIndex in
            coordinator?.makeHeaderMenu(clickedColumnIndex: columnIndex) ?? NSMenu(title: "Columns")
        }
        headerView.autoSizeColumnHandler = { [weak coordinator = context.coordinator] columnIndex in
            coordinator?.autoSizeColumn(at: columnIndex)
        }

        context.coordinator.attach(tableView: tableView)
        context.coordinator.installColumns()

        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.reload()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let columnResizeAnimationSteps = 12
        private let columnResizeIntervalNanoseconds: UInt64 = 24_000_000
        private let autoSizeSampleLimit = 200
        private let autoSizeDebounceNanoseconds: UInt64 = 120_000_000

        private struct AutoSizeSignature: Equatable {
            let trackIDs: [TrackItem.ID]
            let widthHints: PlaylistColumnWidthHints?
            let fontSize: CGFloat
            let monospace: Bool
        }

        private enum Column: String, CaseIterable {
            case transport
            case index
            case file
            case title
            case game
            case author
            case system
            case path
            case length
            case fileSize

            var title: String {
                switch self {
                case .transport: ""
                case .index: "#"
                case .file: "File"
                case .title: "Title"
                case .game: "Game"
                case .author: "Author"
                case .system: "System"
                case .path: "Path"
                case .length: "Length"
                case .fileSize: "Size"
                }
            }

            var defaultWidth: CGFloat {
                switch self {
                case .transport: 32
                case .index: 36
                case .file: 220
                case .title: 220
                case .game: 220
                case .author: 150
                case .system: 80
                case .path: 320
                case .length: 70
                case .fileSize: 80
                }
            }

            var minWidth: CGFloat {
                switch self {
                case .transport: 32
                case .index: 32
                case .file, .title, .game: 120
                case .author: 90
                case .system: 60
                case .path: 160
                case .length: 60
                case .fileSize: 60
                }
            }

            var userConfigurable: Bool {
                self != .transport
            }

            var sortColumn: PlayerViewModel.PlaylistSortColumn? {
                switch self {
                case .transport:
                    nil
                case .index:
                    .index
                case .file:
                    .file
                case .title:
                    .title
                case .game:
                    .game
                case .author:
                    .author
                case .system:
                    .system
                case .path:
                    .path
                case .length:
                    .length
                case .fileSize:
                    nil
                }
            }
        }

        @Bindable var model: PlayerViewModel
        private weak var tableView: NSTableView?
        private var suppressSelectionSync = false
        private var lastAppliedMetadataLoadToken = -1
        private var lastVisibleTrackIDs: [String] = []
        private var lastSelectedTrackIDs: Set<String> = []
        private var lastPrimarySelectedTrackID: String?
        private var lastCurrentTrackID: String?
        private var lastIsPlaying = false
        private var lastSortColumn: PlayerViewModel.PlaylistSortColumn?
        private var lastSortDirection: PlayerViewModel.PlaylistSortDirection = .ascending
        private var lastFontSize: CGFloat?
        private var lastTextColor: PlayerViewModel.DatabaseSidebarTextColor?
        private var lastMonospaceFont: Bool?
        private var lastAutoSizeSignature: AutoSizeSignature?
        private var pendingAutoSizeSignature: AutoSizeSignature?
        private var autoSizeTask: Task<Void, Never>?
        private var suppressWidthPersistence = false
        private var columnResizeTask: Task<Void, Never>?

        init(model: PlayerViewModel) {
            self._model = Bindable(model)
        }

        func attach(tableView: NSTableView) {
            self.tableView = tableView
        }

        func installColumns() {
            guard let tableView else { return }

            tableView.tableColumns.forEach { tableView.removeTableColumn($0) }

            for column in resolvedColumnOrder() {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
                tableColumn.headerCell = SortableTableHeaderCell(textCell: column.title)
                tableColumn.minWidth = column.minWidth
                tableColumn.width = storedWidth(for: column) ?? column.defaultWidth
                tableColumn.resizingMask = column.userConfigurable ? [.userResizingMask] : []
                tableView.addTableColumn(tableColumn)
            }

            refreshSortIndicators()
            reload()
        }

        func reload() {
            guard let tableView else { return }

            applyVisibility(to: tableView)
            refreshSortIndicators()
            let visibleTrackIDs = model.visiblePlaylist.map(\.id)
            let selectedTrackIDs = model.selectedTrackIDs
            let primarySelectedTrackID = model.selectedTrackID
            let currentTrackID = model.currentTrack?.id
            let isPlaying = model.isPlaying
            let sortColumn = model.playlistSortColumn
            let sortDirection = model.playlistSortDirection
            let metadataTokenChanged = model.playlistMetadataLoadToken != lastAppliedMetadataLoadToken
            let rowsChanged = visibleTrackIDs != lastVisibleTrackIDs
            let playbackStateChanged = currentTrackID != lastCurrentTrackID || isPlaying != lastIsPlaying
            let sortChanged = sortColumn != lastSortColumn || sortDirection != lastSortDirection
            let fontChanged = model.playlistFontSize != lastFontSize
                || model.playlistTextColor != lastTextColor
                || model.playlistMonospaceFont != lastMonospaceFont
            let rowHeight = max(18, model.playlistFontSize + 6)
            if tableView.rowHeight != rowHeight {
                tableView.rowHeight = rowHeight
            }

            if rowsChanged || sortChanged || fontChanged {
                tableView.reloadData()
            } else {
                if metadataTokenChanged {
                    reloadMetadataRows(
                        in: tableView,
                        trackIDs: model.playlistMetadataChangedTrackIDs
                    )
                }
                if playbackStateChanged {
                    reloadVisibleRows(in: tableView)
                }
            }

            if rowsChanged || selectedTrackIDs != lastSelectedTrackIDs || primarySelectedTrackID != lastPrimarySelectedTrackID {
                syncSelection(in: tableView)
            } else if rowsChanged || sortChanged {
                tableView.layoutSubtreeIfNeeded()
            }

            if metadataTokenChanged {
                lastAppliedMetadataLoadToken = model.playlistMetadataLoadToken
            }

            scheduleAutomaticColumnSizing(
                signature: AutoSizeSignature(
                    trackIDs: visibleTrackIDs,
                    widthHints: model.playlistColumnWidthHints,
                    fontSize: model.playlistFontSize,
                    monospace: model.playlistMonospaceFont
                )
            )

            lastVisibleTrackIDs = visibleTrackIDs
            lastSelectedTrackIDs = selectedTrackIDs
            lastPrimarySelectedTrackID = primarySelectedTrackID
            lastCurrentTrackID = currentTrackID
            lastIsPlaying = isPlaying
            lastSortColumn = sortColumn
            lastSortDirection = sortDirection
            lastFontSize = model.playlistFontSize
            lastTextColor = model.playlistTextColor
            lastMonospaceFont = model.playlistMonospaceFont
        }

        nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
            MainActor.assumeIsolated {
                model.visiblePlaylist.count
            }
        }

        nonisolated func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            MainActor.assumeIsolated {
                max(18, model.playlistFontSize + 6)
            }
        }

        nonisolated func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            MainActor.assumeIsolated {
                row >= 0 && row < model.visiblePlaylist.count
            }
        }

        func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
            let rowCount = model.visiblePlaylist.count
            let canDrag = model.canDragReorderTracks
            guard canDrag else { return false }

            let rows = rowIndexes.filter { $0 >= 0 && $0 < rowCount }
            guard !rows.isEmpty else { return false }

            pasteboard.clearContents()
            let payload = rows.map(String.init).joined(separator: ",")
            pasteboard.setString(payload, forType: playlistRowDragType)
            return true
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            if info.draggingPasteboard.availableType(from: [databaseFileSidebarDragType]) != nil {
                return .copy
            }
            let canDrag = model.canDragReorderTracks
            let hasDragType = info.draggingPasteboard.availableType(from: [playlistRowDragType]) != nil
            if canDrag,
               dropOperation == .above,
               hasDragType {
                tableView.setDropRow(row, dropOperation: .above)
                return .move
            }

            return droppedFileURLs(from: info).isEmpty ? [] : .copy
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            if let data = info.draggingPasteboard.data(forType: databaseFileSidebarDragType),
               let payload = try? JSONDecoder().decode(DatabaseFileSidebarDragPayload.self, from: data) {
                model.appendDatabaseFileSidebarDrag(payload)
                return true
            }
            let canDrag = model.canDragReorderTracks
            let hasPayload = info.draggingPasteboard.string(forType: playlistRowDragType) != nil
            if canDrag,
               dropOperation == .above,
               hasPayload {
                model.moveSelectedTracks(toPlaylistIndex: row)
                reload()
                return true
            }

            let urls = droppedFileURLs(from: info)
            guard !urls.isEmpty else { return false }
            model.importDroppedURLs(urls)
            return true
        }

        nonisolated func tableViewSelectionDidChange(_ notification: Notification) {
            MainActor.assumeIsolated {
                guard !suppressSelectionSync, let tableView else { return }
                let rows = tableView.selectedRowIndexes.filter { $0 >= 0 && $0 < model.visiblePlaylist.count }
                let trackIDs = rows.map { model.visiblePlaylist[$0].id }
                let primaryTrackID = rows.last.flatMap { row in
                    row >= 0 && row < model.visiblePlaylist.count ? model.visiblePlaylist[row].id : nil
                }
                model.handlePlaylistSelection(trackIDs: trackIDs, primaryTrackID: primaryTrackID)
                // Arrow-key movement is already authoritative in NSTableView.
                // Mark the model snapshot as applied so the SwiftUI update that
                // follows does not immediately reselect the previous row.
                lastSelectedTrackIDs = model.selectedTrackIDs
                lastPrimarySelectedTrackID = model.selectedTrackID
            }
        }

        nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            MainActor.assumeIsolated {
                guard row >= 0, row < model.visiblePlaylist.count, let tableColumn,
                      let column = Column(rawValue: tableColumn.identifier.rawValue) else {
                    return nil
                }

                let track = model.visiblePlaylist[row]

                switch column {
                case .transport:
                    let cell = makeTransportCell(in: tableView)
                    transportButton(in: cell)?.tag = row
                    transportButton(in: cell)?.image = NSImage(
                        systemSymbolName: model.currentTrack?.id == track.id && model.isPlaying ? "stop.fill" : "play.fill",
                        accessibilityDescription: nil
                    )
                    transportButton(in: cell)?.contentTintColor =
                        model.currentTrack?.id == track.id ? NSColor.labelColor : NSColor.secondaryLabelColor
                    return cell
                case .index:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: model.indexText(for: track), isCurrentTrack: model.currentTrack?.id == track.id, monospace: true)
                case .file:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: track.filename, isCurrentTrack: model.currentTrack?.id == track.id)
                case .title:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: model.titleText(for: track), isCurrentTrack: model.currentTrack?.id == track.id)
                case .game:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: model.gameText(for: track), isCurrentTrack: model.currentTrack?.id == track.id)
                case .author:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: model.authorText(for: track), isCurrentTrack: model.currentTrack?.id == track.id)
                case .system:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: model.systemText(for: track), isCurrentTrack: model.currentTrack?.id == track.id)
                case .path:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: model.pathText(for: track), isCurrentTrack: model.currentTrack?.id == track.id)
                case .length:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: model.lengthText(for: track), isCurrentTrack: model.currentTrack?.id == track.id, monospace: true)
                case .fileSize:
                    return configuredTextCell(in: tableView, row: row, identifier: column.rawValue, text: value(for: column, track: track), isCurrentTrack: model.currentTrack?.id == track.id, monospace: true)
                }
            }
        }

        nonisolated func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
            MainActor.assumeIsolated {
                guard column >= 0, column < tableView.tableColumns.count,
                      let playlistColumn = Column(rawValue: tableView.tableColumns[column].identifier.rawValue) else {
                    return 0
                }

                let headerWidth = textWidth(playlistColumn.title, font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold))
                let contentWidth = widestWidth(for: playlistColumn)
                return max(headerWidth, contentWidth) + 20
            }
        }

        nonisolated func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
            MainActor.assumeIsolated {
                guard columnIndex >= 0, columnIndex < tableView.tableColumns.count,
                      let column = Column(rawValue: tableView.tableColumns[columnIndex].identifier.rawValue) else {
                    return false
                }

                return column.userConfigurable
            }
        }

        nonisolated func tableView(_ tableView: NSTableView, userCanChangeVisibilityOf tableColumn: NSTableColumn) -> Bool {
            MainActor.assumeIsolated {
                guard let column = Column(rawValue: tableColumn.identifier.rawValue) else { return false }
                return column.userConfigurable
            }
        }

        nonisolated func tableView(_ tableView: NSTableView, userDidChangeVisibilityOf tableColumns: [NSTableColumn]) {
            MainActor.assumeIsolated {
                persistVisibility()
            }
        }

        nonisolated func tableViewColumnDidMove(_ notification: Notification) {
            MainActor.assumeIsolated {
                persistOrder()
            }
        }

        nonisolated func tableViewColumnDidResize(_ notification: Notification) {
            MainActor.assumeIsolated {
                guard !suppressWidthPersistence else { return }
                persistWidths()
            }
        }

        nonisolated func tableView(_ tableView: NSTableView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
            MainActor.assumeIsolated {
                guard let column = Column(rawValue: tableColumn.identifier.rawValue),
                      let sortColumn = column.sortColumn else {
                    return
                }

                model.togglePlaylistSort(by: sortColumn)
                refreshSortIndicators()
                tableView.reloadData()
                syncSelection(in: tableView)
            }
        }

        @objc
        nonisolated func handleDoubleClick(_ sender: NSTableView) {
            MainActor.assumeIsolated {
                let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
                activateRow(row)
            }
        }

        @objc
        nonisolated func handleTransportButton(_ sender: NSButton) {
            MainActor.assumeIsolated {
                let row = sender.tag
                guard row >= 0, row < model.visiblePlaylist.count else { return }
                model.toggleTrackPlayback(model.visiblePlaylist[row])
            }
        }

        private func makeTransportCell(in tableView: NSTableView) -> NSTableCellView {
            let identifier = NSUserInterfaceItemIdentifier(Column.transport.rawValue)
            if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                return existing
            }

            let cell = NSTableCellView()
            cell.identifier = identifier

            let button = NSButton(frame: .zero)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.setButtonType(.momentaryChange)
            button.target = self
            button.action = #selector(handleTransportButton(_:))
            cell.addSubview(button)
            cell.textField = nil
            cell.imageView = nil
            cell.objectValue = nil
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func transportButton(in cell: NSTableCellView) -> NSButton? {
            cell.subviews.compactMap { $0 as? NSButton }.first
        }

        private func configuredTextCell(in tableView: NSTableView, row: Int, identifier: String, text: String, isCurrentTrack: Bool, monospace: Bool = false) -> NSTableCellView {
            let viewID = NSUserInterfaceItemIdentifier(identifier)
            let cell = tableView.makeView(withIdentifier: viewID, owner: nil) as? NSTableCellView ?? {
                let cell = NSTableCellView()
                cell.identifier = viewID

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                textField.usesSingleLineMode = true
                cell.textField = textField
                cell.addSubview(textField)

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])

                return cell
            }()

            cell.textField?.stringValue = text
            cell.textField?.font = model.playlistMonospaceFont
                ? NSFont.monospacedSystemFont(ofSize: model.playlistFontSize, weight: .regular)
                : (monospace
                    ? NSFont.monospacedDigitSystemFont(ofSize: model.playlistFontSize, weight: .regular)
                    : NSFont.systemFont(ofSize: model.playlistFontSize))
            cell.textField?.textColor = isCurrentTrack
                ? .labelColor
                : Self.playlistTextColor(model.playlistTextColor)
            return cell
        }

        private static func playlistTextColor(_ color: PlayerViewModel.DatabaseSidebarTextColor) -> NSColor {
            switch color {
            case .primary: .labelColor
            case .secondary: .secondaryLabelColor
            case .tertiary: .tertiaryLabelColor
            }
        }

        private func syncSelection(in tableView: NSTableView) {
            suppressSelectionSync = true
            defer { suppressSelectionSync = false }

            let rows = IndexSet(model.visiblePlaylist.enumerated().compactMap { index, track in
                model.selectedTrackIDs.contains(track.id) ? index : nil
            })

            guard !rows.isEmpty else {
                tableView.deselectAll(nil)
                return
            }

            tableView.selectRowIndexes(rows, byExtendingSelection: false)
            if let row = rows.last {
                tableView.scrollRowToVisible(row)
            }
        }

        private func applyVisibility(to tableView: NSTableView) {
            let visibility = storedVisibility()
            for column in tableView.tableColumns {
                guard let playlistColumn = Column(rawValue: column.identifier.rawValue), playlistColumn.userConfigurable else {
                    column.isHidden = false
                    continue
                }

                column.isHidden = visibility[playlistColumn.rawValue] == false
            }
        }

        private func reloadVisibleRows(in tableView: NSTableView) {
            let rows = IndexSet(integersIn: 0..<tableView.numberOfRows)
            let columns = IndexSet(integersIn: 0..<tableView.numberOfColumns)
            tableView.reloadData(forRowIndexes: rows, columnIndexes: columns)
        }

        private func reloadMetadataRows(
            in tableView: NSTableView,
            trackIDs: Set<TrackItem.ID>
        ) {
            guard !trackIDs.isEmpty else {
                tableView.reloadData()
                return
            }

            let rows = IndexSet(model.visiblePlaylist.enumerated().compactMap { index, track in
                trackIDs.contains(track.id) ? index : nil
            })
            guard !rows.isEmpty else { return }

            let metadataColumns = IndexSet(tableView.tableColumns.enumerated().compactMap { index, tableColumn in
                guard let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
                return switch column {
                case .title, .game, .author, .system, .length:
                    index
                case .transport, .index, .file, .path, .fileSize:
                    nil
                }
            })
            tableView.reloadData(forRowIndexes: rows, columnIndexes: metadataColumns)
        }

        private func refreshSortIndicators() {
            guard let tableView else { return }

            for tableColumn in tableView.tableColumns {
                guard let column = Column(rawValue: tableColumn.identifier.rawValue),
                      let headerCell = tableColumn.headerCell as? SortableTableHeaderCell else {
                    continue
                }

                if model.playlistSortColumn == column.sortColumn {
                    headerCell.sortDirection = model.playlistSortDirection
                } else {
                    headerCell.sortDirection = nil
                }
            }

            tableView.headerView?.needsDisplay = true
        }

        private func resolvedColumnOrder() -> [Column] {
            let stored = model.pendingPlaylistColumnOrder ?? []
            let mapped = stored.compactMap(Column.init(rawValue:))
            let missing = Column.allCases.filter { !mapped.contains($0) }
            return mapped + missing
        }

        private func storedVisibility() -> [String: Bool] {
            model.pendingPlaylistColumnVisibility ?? [:]
        }

        private func storedWidth(for column: Column) -> CGFloat? {
            let widths = model.pendingPlaylistColumnWidths ?? [:]
            guard let width = widths[column.rawValue] else {
                return nil
            }
            return CGFloat(width)
        }

        private func persistOrder() {
            guard let tableView else { return }
            let order = tableView.tableColumns.map(\.identifier.rawValue)
            model.rememberPlaylistColumnOrder(order)
        }

        private func persistVisibility() {
            guard let tableView else { return }
            let visibility: [String: Bool] = Dictionary(uniqueKeysWithValues: tableView.tableColumns.compactMap { column in
                guard let playlistColumn = Column(rawValue: column.identifier.rawValue), playlistColumn.userConfigurable else {
                    return nil
                }
                return (playlistColumn.rawValue, !column.isHidden)
            })
            model.rememberPlaylistColumnVisibility(visibility)
        }

        private func persistWidths() {
            guard let tableView else { return }
            let widths = Dictionary(uniqueKeysWithValues: tableView.tableColumns.map { ($0.identifier.rawValue, Double($0.width)) })
            model.rememberPlaylistColumnWidths(widths)
        }

        func activateRow(_ row: Int) {
            guard row >= 0, row < model.visiblePlaylist.count else { return }
            let track = model.visiblePlaylist[row]
            model.handlePlaylistSelection(trackIDs: [track.id], primaryTrackID: track.id)
            model.playTrack(track)
        }

        func activateSelectedRow() {
            guard let tableView else { return }
            let row = tableView.selectedRow >= 0
                ? tableView.selectedRow
                : model.selectedTrackID.flatMap { selectedID in
                    model.visiblePlaylist.firstIndex { $0.id == selectedID }
                } ?? -1
            activateRow(row)
            syncSelection(in: tableView)
        }

        func autoSizeColumn(at columnIndex: Int) {
            guard let tableView,
                  columnIndex >= 0, columnIndex < tableView.tableColumns.count else { return }

            let tableColumn = tableView.tableColumns[columnIndex]
            guard Column(rawValue: tableColumn.identifier.rawValue)?.userConfigurable == true else { return }
            applyColumnWidths([(tableColumn, fittedWidth(for: columnIndex, in: tableView))])
        }

        private func scheduleAutomaticColumnSizing(signature: AutoSizeSignature) {
            guard !signature.trackIDs.isEmpty else {
                autoSizeTask?.cancel()
                autoSizeTask = nil
                pendingAutoSizeSignature = nil
                lastAutoSizeSignature = nil
                return
            }
            guard signature != lastAutoSizeSignature,
                  signature != pendingAutoSizeSignature else { return }

            autoSizeTask?.cancel()
            pendingAutoSizeSignature = signature
            autoSizeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.autoSizeDebounceNanoseconds)
                guard !Task.isCancelled,
                      self.pendingAutoSizeSignature == signature else { return }

                self.autoSizeVisibleColumns()
                self.lastAutoSizeSignature = signature
                self.pendingAutoSizeSignature = nil
                self.autoSizeTask = nil
            }
        }

        private func autoSizeVisibleColumns() {
            guard let tableView else { return }
            let targets = tableView.tableColumns.enumerated().compactMap { columnIndex, tableColumn -> (NSTableColumn, CGFloat)? in
                guard !tableColumn.isHidden,
                      Column(rawValue: tableColumn.identifier.rawValue)?.userConfigurable == true else {
                    return nil
                }
                return (tableColumn, fittedWidth(for: columnIndex, in: tableView))
            }
            applyColumnWidths(targets)
        }

        private func fittedWidth(for columnIndex: Int, in tableView: NSTableView) -> CGFloat {
            let tableColumn = tableView.tableColumns[columnIndex]
            let measuredWidth = self.tableView(tableView, sizeToFitWidthOfColumn: columnIndex)
            let upperBound = tableColumn.maxWidth > 0 ? tableColumn.maxWidth : measuredWidth
            return min(max(measuredWidth, tableColumn.minWidth), upperBound)
        }

        private func applyColumnWidths(_ targets: [(NSTableColumn, CGFloat)]) {
            guard !targets.isEmpty else { return }

            columnResizeTask?.cancel()
            let startWidths = targets.map { $0.0.width }
            let steps = columnResizeAnimationSteps
            suppressWidthPersistence = true

            columnResizeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                for step in 1...steps {
                    try? await Task.sleep(nanoseconds: self.columnResizeIntervalNanoseconds)
                    guard !Task.isCancelled else { return }
                    let linearProgress = CGFloat(step) / CGFloat(steps)
                    let progress = linearProgress < 0.5
                        ? 2 * linearProgress * linearProgress
                        : 1 - (pow(-2 * linearProgress + 2, 2) / 2)
                    for (index, target) in targets.enumerated() {
                        let (tableColumn, finalWidth) = target
                        tableColumn.width = startWidths[index] + ((finalWidth - startWidths[index]) * progress)
                    }
                }

                guard !Task.isCancelled else { return }
                self.suppressWidthPersistence = false
                self.persistWidths()
                self.columnResizeTask = nil
            }
        }

        private func droppedFileURLs(from info: NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true
            ]
            let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: options
            ) as? [URL] ?? []
            return urls
                .map(\.standardizedFileURL)
                .filter(PlaylistQueueLoader.canImportDroppedURL(_:))
        }

        func makeHeaderMenu(clickedColumnIndex: Int) -> NSMenu {
            let menu = NSMenu(title: "Columns")
            menu.autoenablesItems = false

            if let tableView,
               clickedColumnIndex >= 0,
               clickedColumnIndex < tableView.tableColumns.count,
               let clickedColumn = Column(rawValue: tableView.tableColumns[clickedColumnIndex].identifier.rawValue),
               clickedColumn.userConfigurable {
                let autoSizeColumn = NSMenuItem(
                    title: "Auto Size \(clickedColumn.title)",
                    action: #selector(autoSizeColumnFromMenu(_:)),
                    keyEquivalent: ""
                )
                autoSizeColumn.target = self
                autoSizeColumn.representedObject = clickedColumn.rawValue
                menu.addItem(autoSizeColumn)
            }

            let autoSizeAll = NSMenuItem(
                title: "Auto Size All Columns",
                action: #selector(autoSizeAllColumnsFromMenu(_:)),
                keyEquivalent: ""
            )
            autoSizeAll.target = self
            menu.addItem(autoSizeAll)
            menu.addItem(.separator())

            for tableColumn in tableView?.tableColumns ?? [] {
                guard let column = Column(rawValue: tableColumn.identifier.rawValue), column.userConfigurable else {
                    continue
                }

                let item = NSMenuItem(title: column.title, action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
                item.target = self
                item.state = tableColumn.isHidden ? .off : .on
                item.representedObject = tableColumn.identifier.rawValue
                menu.addItem(item)
            }

            return menu
        }

        func makeRowMenu(clickedRow: Int) -> NSMenu {
            let menu = NSMenu(title: "Playlist")
            menu.autoenablesItems = false

            if clickedRow >= 0, clickedRow < model.visiblePlaylist.count {
                let playNow = NSMenuItem(title: "Play Now", action: #selector(playNowFromMenu(_:)), keyEquivalent: "")
                playNow.target = self
                playNow.representedObject = clickedRow
                menu.addItem(playNow)
                menu.addItem(.separator())
            }

            let moveUp = NSMenuItem(title: "Move Up", action: #selector(moveSelectedUp(_:)), keyEquivalent: "")
            moveUp.target = self
            moveUp.isEnabled = model.canMoveSelectedTracksUp
            menu.addItem(moveUp)

            let moveDown = NSMenuItem(title: "Move Down", action: #selector(moveSelectedDown(_:)), keyEquivalent: "")
            moveDown.target = self
            moveDown.isEnabled = model.canMoveSelectedTracksDown
            menu.addItem(moveDown)

            menu.addItem(.separator())

            let cut = NSMenuItem(title: "Cut Tracks", action: #selector(cutSelected(_:)), keyEquivalent: "")
            cut.target = self
            cut.isEnabled = model.canCutSelectedTracks
            menu.addItem(cut)

            let paste = NSMenuItem(title: "Paste Tracks", action: #selector(pasteTracks(_:)), keyEquivalent: "")
            paste.target = self
            paste.isEnabled = model.canPasteTracks
            menu.addItem(paste)

            let exportAAC = NSMenuItem(title: "Export AAC…", action: #selector(exportAAC(_:)), keyEquivalent: "")
            exportAAC.target = self
            exportAAC.representedObject = clickedRow
            exportAAC.isEnabled = clickedRow >= 0 && clickedRow < model.visiblePlaylist.count
            menu.addItem(exportAAC)

            let showInFinder = NSMenuItem(title: "Show in Finder", action: #selector(showSelectedInFinder(_:)), keyEquivalent: "")
            showInFinder.target = self
            showInFinder.isEnabled = model.canShowSelectedTracksInFinder
            menu.addItem(showInFinder)

            let remove = NSMenuItem(title: "Remove Tracks", action: #selector(removeSelected(_:)), keyEquivalent: "")
            remove.target = self
            remove.isEnabled = model.canCutSelectedTracks
            menu.addItem(remove)

            return menu
        }

        @objc
        private func playNowFromMenu(_ sender: NSMenuItem) {
            guard let row = sender.representedObject as? Int,
                  row >= 0, row < model.visiblePlaylist.count else { return }
            activateRow(row)
        }

        @objc
        private func moveSelectedUp(_ sender: NSMenuItem) {
            model.moveSelectedTracksUp()
            reload()
        }

        @objc
        private func moveSelectedDown(_ sender: NSMenuItem) {
            model.moveSelectedTracksDown()
            reload()
        }

        @objc
        private func cutSelected(_ sender: NSMenuItem) {
            model.cutSelectedTracks()
            reload()
        }

        @objc
        private func pasteTracks(_ sender: NSMenuItem) {
            model.pasteTracksFromClipboard()
            reload()
        }

        @objc
        private func exportAAC(_ sender: NSMenuItem) {
            guard let row = sender.representedObject as? Int,
                  row >= 0, row < model.visiblePlaylist.count else { return }

            let clickedTrack = model.visiblePlaylist[row]
            let tracksToExport: [TrackItem]
            if model.selectedTrackIDs.contains(clickedTrack.id) {
                tracksToExport = model.visiblePlaylist.filter { model.selectedTrackIDs.contains($0.id) }
            } else {
                tracksToExport = [clickedTrack]
            }

            model.exportTracksToAAC(tracksToExport)
        }

        @objc
        private func showSelectedInFinder(_ sender: NSMenuItem) {
            model.showSelectedTracksInFinder()
        }

        @objc
        private func removeSelected(_ sender: NSMenuItem) {
            model.deleteSelectedTracks()
            reload()
        }

        @objc
        private func toggleColumnVisibility(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let tableView,
                  let tableColumn = tableView.tableColumns.first(where: { $0.identifier.rawValue == rawValue }) else {
                return
            }

            tableColumn.isHidden.toggle()
            persistVisibility()
        }

        @objc
        private func autoSizeColumnFromMenu(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let tableView,
                  let columnIndex = tableView.tableColumns.firstIndex(where: {
                      $0.identifier.rawValue == rawValue
                  }) else { return }
            autoSizeColumn(at: columnIndex)
        }

        @objc
        private func autoSizeAllColumnsFromMenu(_ sender: NSMenuItem) {
            autoSizeVisibleColumns()
        }

        private func widestWidth(for column: Column) -> CGFloat {
            let font = model.playlistMonospaceFont
                ? NSFont.monospacedSystemFont(ofSize: model.playlistFontSize, weight: .regular)
                : (column == .index || column == .length
                    ? NSFont.monospacedDigitSystemFont(ofSize: model.playlistFontSize, weight: .regular)
                    : NSFont.systemFont(ofSize: model.playlistFontSize))

            let sample = model.visiblePlaylist.prefix(autoSizeSampleLimit)
            let sampledWidth = sample.reduce(CGFloat.zero) { currentMax, track in
                max(currentMax, textWidth(value(for: column, track: track), font: font))
            }
            let hintedWidth = widthHintValue(for: column).map {
                textWidth($0, font: font)
            } ?? 0
            return max(sampledWidth, hintedWidth)
        }

        private func widthHintValue(for column: Column) -> String? {
            guard let hints = model.playlistColumnWidthHints else { return nil }
            return switch column {
            case .transport:
                nil
            case .index:
                hints.indexText
            case .file:
                hints.fileText
            case .title:
                hints.titleText
            case .game:
                hints.gameText
            case .author:
                hints.authorText
            case .system:
                hints.systemText
            case .path:
                nil
            case .length:
                hints.lengthText
            case .fileSize:
                nil
            }
        }

        private func value(for column: Column, track: TrackItem) -> String {
            switch column {
            case .transport:
                ""
            case .index:
                model.indexText(for: track)
            case .file:
                track.filename
            case .title:
                model.titleText(for: track)
            case .game:
                model.gameText(for: track)
            case .author:
                model.authorText(for: track)
            case .system:
                model.systemText(for: track)
            case .path:
                model.pathText(for: track)
            case .length:
                model.lengthText(for: track)
            case .fileSize:
                fileSizeText(for: track)
            }
        }

        private func fileSizeText(for track: TrackItem) -> String {
            guard !track.isArchiveEntry else { return "—" }
            let bytes = (try? track.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
            guard let bytes, bytes > 0 else { return "—" }
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }

        private func textWidth(_ text: String, font: NSFont) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            return (text as NSString).size(withAttributes: attributes).width
        }
    }
}

private let playlistRowDragType = NSPasteboard.PasteboardType("com.cocoaspice.playlist-row")

extension PlaylistTableView.Coordinator: @preconcurrency NSTableViewDataSource, NSTableViewDelegate {
}

@MainActor
private final class PlaylistNativeTableView: NSTableView {
    var rowActivationHandler: ((Int) -> Void)?
    var returnActivationHandler: (() -> Void)?
    var rowMenuProvider: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            returnActivationHandler?()
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: localPoint)

        super.mouseDown(with: event)

        if event.clickCount == 2, clickedRow >= 0 {
            rowActivationHandler?(clickedRow)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let localPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: localPoint)
        guard clickedRow >= 0 else { return super.menu(for: event) }

        if !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return rowMenuProvider?(clickedRow) ?? super.menu(for: event)
    }
}

private final class SortableTableHeaderCell: NSTableHeaderCell {
    var sortDirection: PlayerViewModel.PlaylistSortDirection?

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: textColor ?? NSColor.headerTextColor,
            .paragraphStyle: paragraphStyle
        ]

        let attributedTitle = NSAttributedString(string: stringValue, attributes: attributes)
        let titleSize = attributedTitle.size()
        let titleFrame = NSRect(
            x: cellFrame.origin.x,
            y: cellFrame.origin.y + floor((cellFrame.height - titleSize.height) / 2.0),
            width: cellFrame.width,
            height: titleSize.height
        )

        attributedTitle.draw(in: titleFrame)

        guard let sortDirection,
              let image = NSImage(
                systemSymbolName: sortDirection == .ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill",
                accessibilityDescription: nil
              ) else {
            return
        }

        let indicatorRect = NSRect(
            x: cellFrame.minX + 6,
            y: cellFrame.minY + floor((cellFrame.height - 8) / 2.0),
            width: 8,
            height: 8
        )
        image.draw(in: indicatorRect)
    }
}

@MainActor
private final class PlaylistTableHeaderView: NSTableHeaderView {
    var headerMenuProvider: ((Int) -> NSMenu)?
    var autoSizeColumnHandler: ((Int) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: point)
        return headerMenuProvider?(columnIndex)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if event.clickCount == 2, let columnIndex = dividerColumn(at: point) {
            autoSizeColumnHandler?(columnIndex)
            return
        }

        super.mouseDown(with: event)
    }

    private func dividerColumn(at point: NSPoint) -> Int? {
        guard let tableView else { return nil }

        for columnIndex in 0..<tableView.numberOfColumns {
            let rect = headerRect(ofColumn: columnIndex)
            if abs(point.x - rect.maxX) <= 4 {
                return columnIndex
            }
        }

        return nil
    }
}
