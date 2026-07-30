import AppKit
import SwiftUI

let databaseFileSidebarDragType = NSPasteboard.PasteboardType("com.cocoaspice.database-file-sidebar-items")

struct MainView: View {
    @Bindable var model: PlayerViewModel

    var body: some View {
        liveMainView
        .frame(minWidth: 320, minHeight: 240)
        .background(WindowToolbarSpectrumAccessory(model: model.toolbarSpectrum))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.setSidebarBrowserMode(model.sidebarBrowserMode == .games ? .files : .games)
                } label: {
                    Image(systemName: model.sidebarBrowserMode == .games ? "folder" : "square.grid.2x2")
                }
                .help(model.sidebarBrowserMode == .games ? "Show Files" : "Show Games")
                .accessibilityLabel(model.sidebarBrowserMode == .games ? "Show Files" : "Show Games")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .disabled(model.playlist.isEmpty)

                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(model.currentTrack == nil || model.isLoading)

                Button {
                    model.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .disabled(model.playlist.isEmpty)

            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.longPlayEnabled.toggle()
                    model.toggleLongPlayEnabled()
                } label: {
                    Image(systemName: "infinity")
                        .foregroundStyle(model.longPlayEnabled ? .primary : .secondary)
                }
                .help(model.longPlayEnabled ? "Long Play: On" : "Long Play: Off")
                .accessibilityLabel(model.longPlayEnabled ? "Turn Long Play Off" : "Turn Long Play On")

                Button {
                    model.cycleRepeatMode()
                } label: {
                    Image(systemName: model.repeatMode.iconName)
                        .foregroundStyle(model.repeatMode == .off ? .secondary : .primary)
                }
                .help(model.repeatMode.title)
                .accessibilityLabel(model.repeatMode.title)

                Button {
                    model.cycleRandomPlaybackScope()
                } label: {
                    Image(systemName: model.randomPlaybackScope.iconName)
                }
                .help(model.randomPlaybackScope.title)
                .accessibilityLabel(model.randomPlaybackScope.title)
                .disabled(model.playlist.isEmpty && model.databaseGameItems.isEmpty)

                Button {
                    model.toggleEqualizerEnabled()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(model.equalizerEnabled ? .primary : .secondary)
                }
                .help(model.equalizerEnabled ? "Equalizer: On" : "Equalizer: Off")
                .accessibilityLabel(model.equalizerEnabled ? "Turn Equalizer Off" : "Turn Equalizer On")
            }
        }
    }

    private var liveMainView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                NativeSearchField(
                    text: $model.sidebarSearchText,
                    placeholder: model.sidebarBrowserMode == .games ? "Search Database" : "Search Files",
                    debounceInterval: 0.1
                )
                .padding(.horizontal, 8)
                .padding(.top, 0)
                .padding(.bottom, 2)

                Group {
                    if model.isLoadingDatabaseSidebar {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading Library…")
                                .font(.headline)
                            Text("Preparing the \(model.sidebarBrowserMode == .games ? "game" : "file") sidebar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.sidebarBrowserMode == .games && model.databaseGameItems.isEmpty {
                        if model.isLibraryScanInProgress {
                            ContentUnavailableView(
                                "Scanning Database",
                                systemImage: "books.vertical",
                                description: Text("The sidebar will populate after the current scan commits its results.")
                            )
                        } else {
                            ContentUnavailableView(
                                "No Database Games",
                                systemImage: "books.vertical",
                                description: Text("Add scan roots in Options to populate the database.")
                            )
                        }
                    } else if model.sidebarBrowserMode == .files && model.databaseFileItems.isEmpty {
                        ContentUnavailableView(
                            "No Database Files",
                            systemImage: "folder",
                            description: Text("Add scan roots in Options to populate the database.")
                        )
                    } else if model.sidebarBrowserMode == .games && model.visibleDatabaseGameItems.isEmpty {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "magnifyingglass",
                            description: Text("No database games match the current sidebar search.")
                        )
                    } else if model.sidebarBrowserMode == .files && model.visibleDatabaseFileItems.isEmpty {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "magnifyingglass",
                            description: Text("No scanned files match the current sidebar search.")
                        )
                    } else if model.sidebarBrowserMode == .games {
                        DatabaseGameListView(
                            model: model,
                            sidebarFontSize: model.databaseSidebarFontSize,
                            sidebarTextColor: model.databaseSidebarTextColor,
                            sidebarMonospace: model.databaseSidebarMonospaceFont
                        )
                    } else {
                        DatabaseFileListView(
                            model: model,
                            sidebarFontSize: model.databaseSidebarFontSize,
                            sidebarTextColor: model.databaseSidebarTextColor,
                            sidebarMonospace: model.databaseSidebarMonospaceFont
                        )
                    }
                }
            }
            .navigationSplitViewColumnWidth(ideal: 220, max: 500)
        } detail: {
            VStack(spacing: 0) {
                ZStack {
                    PlaylistTableView(model: model)

                    if model.playlist.isEmpty {
                        ContentUnavailableView("Empty Queue", systemImage: "music.note.list", description: Text("Double-click a game or a folder search result in the sidebar to queue tracks."))
                            .allowsHitTesting(false)
                    }
                }

                Divider()
                statusBar
            }
            .frame(minWidth: 320, minHeight: 240)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(model.statusPathReadout)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Text("\(model.currentTrackDurationReadout) / \(model.elapsedReadout) / \(model.playlistTotalDurationReadout)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Total playlist duration. A + means one or more track durations are still unknown.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct WindowToolbarSpectrumAccessory: NSViewRepresentable {
    let model: ToolbarSpectrumModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> AccessoryProbeView {
        let view = AccessoryProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AccessoryProbeView, context: Context) {
        context.coordinator.model = model
        context.coordinator.installIfNeeded(from: nsView)
        context.coordinator.updateAccessoryView()
    }

    final class Coordinator: NSObject {
        @MainActor var model: ToolbarSpectrumModel
        private weak var window: NSWindow?
        private var hostingView: NSHostingView<ToolbarSpectrumView>?
        private weak var titlebarContainerView: NSView?

        @MainActor
        init(model: ToolbarSpectrumModel) {
            self.model = model
        }

        @MainActor
        func installIfNeeded(from view: NSView) {
            guard let window = view.window else { return }
            if self.window !== window {
                removeSpectrumView()
                self.window = window
            }

            guard hostingView == nil else { return }
            guard let titlebarContainerView = resolveTitlebarContainerView(for: window) else { return }

            let hostingView = NSHostingView(rootView: ToolbarSpectrumView(model: model))
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            titlebarContainerView.addSubview(hostingView)

            NSLayoutConstraint.activate([
                hostingView.trailingAnchor.constraint(equalTo: titlebarContainerView.trailingAnchor, constant: -14),
                hostingView.centerYAnchor.constraint(equalTo: titlebarContainerView.centerYAnchor)
            ])

            self.hostingView = hostingView
            self.titlebarContainerView = titlebarContainerView
        }

        @MainActor
        func updateAccessoryView() {
            guard model.isVisible else {
                removeSpectrumView()
                return
            }
            if hostingView == nil, let window, let container = resolveTitlebarContainerView(for: window) {
                let hostingView = NSHostingView(rootView: ToolbarSpectrumView(model: model))
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(hostingView)
                NSLayoutConstraint.activate([
                    hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
                    hostingView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
                ])
                self.hostingView = hostingView
                self.titlebarContainerView = container
            }
            hostingView?.rootView = ToolbarSpectrumView(model: model)
        }

        @MainActor
        private func removeSpectrumView() {
            hostingView?.removeFromSuperview()
            hostingView = nil
            titlebarContainerView = nil
        }

        @MainActor
        private func resolveTitlebarContainerView(for window: NSWindow) -> NSView? {
            if let standardButtonSuperview = window.standardWindowButton(.closeButton)?.superview {
                return standardButtonSuperview
            }
            return window.contentView?.superview
        }
    }
}

private final class AccessoryProbeView: NSView {
    weak var coordinator: WindowToolbarSpectrumAccessory.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Task { @MainActor [weak self] in
            guard let self else { return }
            coordinator?.installIfNeeded(from: self)
            coordinator?.updateAccessoryView()
        }
    }
}

@MainActor
private enum DatabaseSidebarTableChrome {
    static func makeTableView(
        rowHeight: CGFloat,
        columnIdentifier: String,
        coordinator: NSObject & NSTableViewDataSource & NSTableViewDelegate,
        doubleAction: Selector,
        activationHandler: @escaping () -> Void,
        rowMenuProvider: @escaping (Int) -> NSMenu?,
        supportsDragging: Bool = false
    ) -> (scrollView: NSScrollView, tableView: DatabaseSidebarNativeTableView) {
        let tableView = DatabaseSidebarNativeTableView(frame: .zero)
        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .regular
        tableView.usesAutomaticRowHeights = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = true
        tableView.backgroundColor = .clear
        tableView.delegate = coordinator
        tableView.dataSource = coordinator
        tableView.doubleAction = doubleAction
        tableView.target = coordinator
        tableView.activationHandler = activationHandler
        tableView.rowMenuProvider = rowMenuProvider
        if supportsDragging {
            tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
            tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        }

        let column = NSTableColumn(identifier: .init(columnIdentifier))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        return (scrollView, tableView)
    }

    static func textCell(
        in tableView: NSTableView,
        identifier: NSUserInterfaceItemIdentifier
    ) -> NSTableCellView {
        tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.usesSingleLineMode = true
            cell.textField = textField
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }()
    }

    static func textColor(_ color: PlayerViewModel.DatabaseSidebarTextColor) -> NSColor {
        switch color {
        case .secondary: .secondaryLabelColor
        case .primary: .labelColor
        case .tertiary: .tertiaryLabelColor
        }
    }

    static func reloadVisibleRows(in tableView: NSTableView) {
        tableView.reloadData(
            forRowIndexes: IndexSet(integersIn: 0..<tableView.numberOfRows),
            columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
        )
    }
}

private struct DatabaseGameListView: NSViewRepresentable {
    @Bindable var model: PlayerViewModel
    let sidebarFontSize: CGFloat
    let sidebarTextColor: PlayerViewModel.DatabaseSidebarTextColor
    let sidebarMonospace: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            model: model,
            sidebarFontSize: sidebarFontSize,
            sidebarTextColor: sidebarTextColor,
            sidebarMonospace: sidebarMonospace
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let chrome = DatabaseSidebarTableChrome.makeTableView(
            rowHeight: model.databaseSidebarFontSize + 5,
            columnIdentifier: "Game",
            coordinator: context.coordinator,
            doubleAction: #selector(Coordinator.handleDoubleAction(_:)),
            activationHandler: { [weak coordinator = context.coordinator] in
            coordinator?.handleReturnActivation()
            },
            rowMenuProvider: { [weak coordinator = context.coordinator] row in
                coordinator?.makeRowMenu(clickedRow: row)
            }
        )
        context.coordinator.attach(tableView: chrome.tableView)
        return chrome.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.sidebarFontSize = sidebarFontSize
        context.coordinator.sidebarTextColor = sidebarTextColor
        context.coordinator.sidebarMonospace = sidebarMonospace
        context.coordinator.reload()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private enum SidebarRow {
            case system(String, isExpanded: Bool)
            case game(DatabaseGameItem)

            var game: DatabaseGameItem? {
                guard case .game(let item) = self else { return nil }
                return item
            }
        }

        @Bindable var model: PlayerViewModel
        var sidebarFontSize: CGFloat
        var sidebarTextColor: PlayerViewModel.DatabaseSidebarTextColor
        var sidebarMonospace: Bool
        private weak var tableView: DatabaseSidebarNativeTableView?
        private var reloadScheduled = false
        private var cachedSidebarRows: [SidebarRow] = []
        private var lastSidebarContentRevision = -1
        private var lastSidebarSystemMode: Bool?
        private var lastExpandedSystems: Set<String>?
        private var lastSelectionIDs: Set<String> = []
        private var lastFontSize: CGFloat?
        private var lastTextColor: PlayerViewModel.DatabaseSidebarTextColor?
        private var lastMonospace: Bool?

        init(
            model: PlayerViewModel,
            sidebarFontSize: CGFloat,
            sidebarTextColor: PlayerViewModel.DatabaseSidebarTextColor,
            sidebarMonospace: Bool
        ) {
            self._model = Bindable(model)
            self.sidebarFontSize = sidebarFontSize
            self.sidebarTextColor = sidebarTextColor
            self.sidebarMonospace = sidebarMonospace
        }

        func attach(tableView: DatabaseSidebarNativeTableView) {
            self.tableView = tableView
        }

        func reload() {
            guard let tableView else { return }
            let sidebarContentRevision = model.databaseSidebar.contentRevision
            let expandedSystems = model.expandedDatabaseSystems
            let sidebarDataChanged = sidebarContentRevision != lastSidebarContentRevision
                || model.sidebarSystemMode != lastSidebarSystemMode
                || expandedSystems != lastExpandedSystems
            let needsContentReload = sidebarDataChanged
                || sidebarFontSize != lastFontSize
                || sidebarTextColor != lastTextColor
                || sidebarMonospace != lastMonospace
            let selectionChanged = model.selectedDatabaseGameIDs != lastSelectionIDs
            guard needsContentReload || selectionChanged else { return }

            lastSelectionIDs = model.selectedDatabaseGameIDs
            lastFontSize = sidebarFontSize
            lastTextColor = sidebarTextColor
            lastMonospace = sidebarMonospace

            if sidebarDataChanged {
                cachedSidebarRows = makeSidebarRows()
                lastSidebarContentRevision = sidebarContentRevision
                lastSidebarSystemMode = model.sidebarSystemMode
                lastExpandedSystems = expandedSystems
            }

            guard needsContentReload else {
                syncSelection(in: tableView)
                return
            }

            guard !reloadScheduled else { return }
            reloadScheduled = true

            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                self.reloadScheduled = false
                tableView.reloadData()
                self.syncSelection(in: tableView)
            }
        }

        private func syncSelection(in tableView: NSTableView) {
            let rows = IndexSet(cachedSidebarRows.enumerated().compactMap { index, row in
                row.game.flatMap { model.selectedDatabaseGameIDs.contains($0.id) ? index : nil }
            })

            if !rows.isEmpty {
                if tableView.selectedRowIndexes != rows {
                    tableView.selectRowIndexes(rows, byExtendingSelection: false)
                }
                if let row = rows.last {
                    tableView.scrollRowToVisible(row)
                }
            } else if tableView.selectedRow != -1 {
                tableView.deselectAll(nil)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            cachedSidebarRows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            sidebarFontSize + 5
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard row >= 0, row < cachedSidebarRows.count else { return false }
            if case .system(let systemName, _) = cachedSidebarRows[row] {
                model.toggleDatabaseSystemExpansion(systemName)
                reload()
                return false
            }
            return true
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < cachedSidebarRows.count else { return nil }
            let rowItem = cachedSidebarRows[row]
            let identifier = NSUserInterfaceItemIdentifier("DatabaseGameCell")
            let cell = DatabaseSidebarTableChrome.textCell(in: tableView, identifier: identifier)

            switch rowItem {
            case .system(let systemName, let isExpanded):
                cell.textField?.stringValue = "\(isExpanded ? "▾" : "▸")  \(systemName)"
                cell.textField?.font = sidebarMonospace
                    ? .monospacedSystemFont(ofSize: sidebarFontSize, weight: .semibold)
                    : .boldSystemFont(ofSize: sidebarFontSize)
            case .game(let item):
                cell.textField?.stringValue = model.sidebarSystemMode ? "    \(item.name)" : item.displayName
                cell.textField?.font = sidebarMonospace
                    ? .monospacedSystemFont(ofSize: sidebarFontSize, weight: .regular)
                    : .systemFont(ofSize: sidebarFontSize)
            }
            cell.textField?.textColor = DatabaseSidebarTableChrome.textColor(sidebarTextColor)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            let rows = tableView.selectedRowIndexes.filter { $0 >= 0 && $0 < cachedSidebarRows.count }
            let items = rows.compactMap { cachedSidebarRows[$0].game }
            let ids = items.map(\.id)
            let primaryID = items.last?.id
            model.selectDatabaseGames(ids: ids, primaryID: primaryID)
            reloadVisibleRows()
        }

        @objc func handleDoubleAction(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < cachedSidebarRows.count else { return }
            if case .system(let systemName, _) = cachedSidebarRows[row] {
                model.toggleDatabaseSystemExpansion(systemName)
                reload()
                return
            }
            guard let item = cachedSidebarRows[row].game else { return }
            switch model.sidebarDoubleClickAction {
            case .playNow:
                model.activateDatabaseGame(item, replace: true)
            case .enqueue:
                model.activateDatabaseGame(item, replace: false)
            }
        }

        func handleReturnActivation() {
            model.activateSelectedDatabaseGamesWithReturn()
        }

        func makeRowMenu(clickedRow: Int) -> NSMenu? {
            guard clickedRow >= 0, clickedRow < cachedSidebarRows.count,
                  let item = cachedSidebarRows[clickedRow].game else { return nil }
            let menu = NSMenu(title: "Actions")

            let playNow = NSMenuItem(title: "Set as Playlist", action: #selector(handlePlayNow(_:)), keyEquivalent: "")
            playNow.representedObject = item.id
            playNow.target = self
            menu.addItem(playNow)

            let enqueue = NSMenuItem(title: "Add to Playlist", action: #selector(handleEnqueue(_:)), keyEquivalent: "")
            enqueue.representedObject = item.id
            enqueue.target = self
            menu.addItem(enqueue)

            return menu
        }

        @objc private func handlePlayNow(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let item = model.databaseGameItems.first(where: { $0.id == id }) else { return }
            model.activateDatabaseGame(item, replace: true)
        }

        @objc private func handleEnqueue(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let item = model.databaseGameItems.first(where: { $0.id == id }) else { return }
            model.activateDatabaseGame(item, replace: false)
        }

        private func reloadVisibleRows() {
            guard let tableView else { return }
            DatabaseSidebarTableChrome.reloadVisibleRows(in: tableView)
        }

        private func makeSidebarRows() -> [SidebarRow] {
            let items = model.visibleDatabaseGameItems
            guard model.sidebarSystemMode else { return items.map(SidebarRow.game) }

            let grouped = Dictionary(grouping: items, by: model.sidebarSystemName(for:))
            return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .flatMap { systemName in
                    let isExpanded = model.expandedDatabaseSystems.contains(systemName)
                    let children = isExpanded ? (grouped[systemName] ?? []).map(SidebarRow.game) : []
                    return [.system(systemName, isExpanded: isExpanded)] + children
                }
        }
    }
}

private struct DatabaseFileListView: NSViewRepresentable {
    @Bindable var model: PlayerViewModel
    let sidebarFontSize: CGFloat
    let sidebarTextColor: PlayerViewModel.DatabaseSidebarTextColor
    let sidebarMonospace: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            model: model,
            sidebarFontSize: sidebarFontSize,
            sidebarTextColor: sidebarTextColor,
            sidebarMonospace: sidebarMonospace
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let chrome = DatabaseSidebarTableChrome.makeTableView(
            rowHeight: model.databaseSidebarFontSize + 5,
            columnIdentifier: "File",
            coordinator: context.coordinator,
            doubleAction: #selector(Coordinator.handleDoubleAction(_:)),
            activationHandler: { [weak coordinator = context.coordinator] in
                coordinator?.handleReturnActivation()
            },
            rowMenuProvider: { [weak coordinator = context.coordinator] row in
                coordinator?.makeRowMenu(clickedRow: row)
            },
            supportsDragging: true
        )
        context.coordinator.attach(tableView: chrome.tableView)
        return chrome.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.sidebarFontSize = sidebarFontSize
        context.coordinator.sidebarTextColor = sidebarTextColor
        context.coordinator.sidebarMonospace = sidebarMonospace
        context.coordinator.reload()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        @Bindable var model: PlayerViewModel
        var sidebarFontSize: CGFloat
        var sidebarTextColor: PlayerViewModel.DatabaseSidebarTextColor
        var sidebarMonospace: Bool
        private weak var tableView: DatabaseSidebarNativeTableView?
        private var reloadScheduled = false
        private var cachedRows: [DatabaseFileSidebarTree.Row] = []
        private var lastContentRevision = -1
        private var lastExpandedFolderIDs: Set<String> = []
        private var lastSelectionIDs: Set<String> = []
        private var lastSelectedFolders: Set<DatabaseFileSidebarFolder> = []
        private var lastFontSize: CGFloat?
        private var lastTextColor: PlayerViewModel.DatabaseSidebarTextColor?
        private var lastMonospace: Bool?

        init(
            model: PlayerViewModel,
            sidebarFontSize: CGFloat,
            sidebarTextColor: PlayerViewModel.DatabaseSidebarTextColor,
            sidebarMonospace: Bool
        ) {
            self._model = Bindable(model)
            self.sidebarFontSize = sidebarFontSize
            self.sidebarTextColor = sidebarTextColor
            self.sidebarMonospace = sidebarMonospace
        }

        func attach(tableView: DatabaseSidebarNativeTableView) {
            self.tableView = tableView
            tableView.rowClickHandler = { [weak self] row, modifierFlags in
                self?.handleDirectFolderClick(row: row, modifierFlags: modifierFlags) ?? false
            }
        }

        func reload() {
            guard let tableView else { return }
            let contentRevision = model.databaseFileSidebar.contentRevision
            let expandedFolderIDs = model.databaseFileSidebar.expandedFolderIDs
            let treeChanged = contentRevision != lastContentRevision || expandedFolderIDs != lastExpandedFolderIDs
            let needsContentReload = treeChanged
                || sidebarFontSize != lastFontSize
                || sidebarTextColor != lastTextColor
                || sidebarMonospace != lastMonospace
            let selectionChanged = model.selectedDatabaseFileIDs != lastSelectionIDs
                || model.selectedDatabaseFileFolders != lastSelectedFolders
            guard needsContentReload || selectionChanged else { return }

            lastSelectionIDs = model.selectedDatabaseFileIDs
            lastSelectedFolders = model.selectedDatabaseFileFolders
            lastFontSize = sidebarFontSize
            lastTextColor = sidebarTextColor
            lastMonospace = sidebarMonospace
            if treeChanged {
                cachedRows = DatabaseFileSidebarTree.rows(
                    items: model.visibleDatabaseFileItems,
                    expandedFolderIDs: expandedFolderIDs
                )
                lastContentRevision = contentRevision
                lastExpandedFolderIDs = expandedFolderIDs
            }

            guard needsContentReload else {
                syncSelection(in: tableView)
                return
            }
            guard !reloadScheduled else { return }
            reloadScheduled = true
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                self.reloadScheduled = false
                tableView.reloadData()
                self.syncSelection(in: tableView)
            }
        }

        private func syncSelection(in tableView: NSTableView) {
            let rows = IndexSet(cachedRows.enumerated().compactMap { index, row in
                switch row {
                case .file(let item, _):
                    model.selectedDatabaseFileIDs.contains(item.id) ? index : nil
                case .folder(let id, _, _, _):
                    model.selectedDatabaseFileFolders.contains(where: { $0.id == id }) ? index : nil
                }
            })
            if !rows.isEmpty {
                if tableView.selectedRowIndexes != rows {
                    tableView.selectRowIndexes(rows, byExtendingSelection: false)
                }
                if let row = rows.last {
                    tableView.scrollRowToVisible(row)
                }
            } else if tableView.selectedRow != -1 {
                tableView.deselectAll(nil)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            cachedRows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            sidebarFontSize + 5
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard row >= 0, row < cachedRows.count else { return false }
            guard case .file = cachedRows[row] else { return false }
            return true
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < cachedRows.count else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("DatabaseFileCell")
            let cell = DatabaseSidebarTableChrome.textCell(in: tableView, identifier: identifier)

            switch cachedRows[row] {
            case .folder(_, let title, let depth, let isExpanded):
                cell.textField?.stringValue = "\(sidebarIndent(depth))\(isExpanded ? "▾" : "▸")  \(title)"
                cell.textField?.font = sidebarMonospace
                    ? .monospacedSystemFont(ofSize: sidebarFontSize, weight: .semibold)
                    : .boldSystemFont(ofSize: sidebarFontSize)
            case .file(let item, let depth):
                let trackLabel = item.trackCount == 1 ? "1 track" : "\(item.trackCount) tracks"
                cell.textField?.stringValue = "\(sidebarIndent(depth))\(item.filename) • \(trackLabel)"
                cell.textField?.font = sidebarMonospace
                    ? .monospacedSystemFont(ofSize: sidebarFontSize, weight: .regular)
                    : .systemFont(ofSize: sidebarFontSize)
            }
            cell.textField?.textColor = DatabaseSidebarTableChrome.textColor(sidebarTextColor)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            let rows = tableView.selectedRowIndexes.filter { $0 >= 0 && $0 < cachedRows.count }
            let items = rows.compactMap { cachedRows[$0].file }
            let folders = rows.compactMap { row -> DatabaseFileSidebarFolder? in
                guard case .folder(_, _, _, _) = cachedRows[row],
                      let folder = folder(for: cachedRows[row]) else { return nil }
                return folder
            }
            model.selectDatabaseFileSidebarItems(
                fileIDs: items.map(\.id),
                primaryFileID: items.last?.id,
                folders: folders
            )
            if folders.isEmpty, items.count == 1, let archive = items.first, archive.isArchive {
                model.activateDatabaseFile(archive, replace: true)
            }
            reloadVisibleRows()
        }

        @objc func handleDoubleAction(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < cachedRows.count else { return }
            if let folder = folder(for: cachedRows[row]) {
                model.activateDatabaseFileFolder(folder)
                return
            }
            model.activateSelectedDatabaseFilesWithReturn()
        }

        func handleReturnActivation() {
            model.activateSelectedDatabaseFilesWithReturn()
        }

        func makeRowMenu(clickedRow: Int) -> NSMenu? {
            guard clickedRow >= 0, clickedRow < cachedRows.count else { return nil }
            let menu = NSMenu(title: "Actions")
            let showOnDisk = NSMenuItem(title: "Show on Disk", action: #selector(handleShowOnDisk(_:)), keyEquivalent: "")
            showOnDisk.representedObject = fileURL(for: cachedRows[clickedRow])
            showOnDisk.target = self
            menu.addItem(showOnDisk)
            menu.addItem(.separator())
            let playNow = NSMenuItem(title: "Set as Playlist", action: #selector(handlePlayNow(_:)), keyEquivalent: "")
            playNow.target = self
            menu.addItem(playNow)
            let enqueue = NSMenuItem(title: "Add to Playlist", action: #selector(handleEnqueue(_:)), keyEquivalent: "")
            enqueue.target = self
            menu.addItem(enqueue)
            return menu
        }

        @objc private func handlePlayNow(_ sender: NSMenuItem) {
            model.activateSelectedDatabaseFilesWithReturn()
        }

        @objc private func handleEnqueue(_ sender: NSMenuItem) {
            guard let tableView else { return }
            model.appendDatabaseFileSidebarDrag(dragPayload(for: tableView.selectedRowIndexes))
        }

        @objc private func handleShowOnDisk(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            model.showOnDisk(url)
        }

        nonisolated func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
            let data: Data? = MainActor.assumeIsolated { () -> Data? in
                let payload = dragPayload(for: rowIndexes)
                guard !payload.fileIDs.isEmpty || !payload.folders.isEmpty,
                      let data = try? JSONEncoder().encode(payload) else {
                    return nil
                }
                return data
            }
            guard let data else { return false }
            pasteboard.clearContents()
            pasteboard.setData(data, forType: databaseFileSidebarDragType)
            return true
        }

        private func sidebarIndent(_ depth: Int) -> String {
            String(repeating: "    ", count: depth)
        }

        private func handleDirectFolderClick(
            row: Int,
            modifierFlags: NSEvent.ModifierFlags
        ) -> Bool {
            guard row >= 0,
                  row < cachedRows.count,
                  DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: modifierFlags),
                  case .folder(let id, _, _, _) = cachedRows[row] else {
                return false
            }
            model.toggleDatabaseFileFolder(id)
            reload()
            return true
        }

        private func folder(for row: DatabaseFileSidebarTree.Row) -> DatabaseFileSidebarFolder? {
            guard case .folder(_, _, _, _) = row else { return nil }
            guard case .folder(let id, _, _, _) = row,
                  let separator = id.firstIndex(of: "|"),
                  let rootID = Int64(id[..<separator]) else { return nil }
            let path = String(id[id.index(after: separator)...])
            guard let item = model.databaseFileItems.first(where: {
                $0.rootID == rootID && ($0.path == path || $0.path.hasPrefix(path + "/"))
            }) else {
                return nil
            }
            return DatabaseFileSidebarFolder(rootID: rootID, rootPath: item.rootPath, path: path)
        }

        private func fileURL(for row: DatabaseFileSidebarTree.Row) -> URL? {
            switch row {
            case .file(let item, _):
                URL(fileURLWithPath: item.path)
            case .folder:
                folder(for: row).map { URL(fileURLWithPath: $0.path, isDirectory: true) }
            }
        }

        private func dragPayload(for rows: IndexSet) -> DatabaseFileSidebarDragPayload {
            let validRows = rows.filter { $0 >= 0 && $0 < cachedRows.count }
            return DatabaseFileSidebarDragPayload(
                fileIDs: validRows.compactMap { cachedRows[$0].file?.id },
                folders: validRows.compactMap { folder(for: cachedRows[$0]) }
            )
        }

        private func reloadVisibleRows() {
            guard let tableView else { return }
            DatabaseSidebarTableChrome.reloadVisibleRows(in: tableView)
        }
    }
}

@MainActor
private final class DatabaseSidebarNativeTableView: NSTableView {
    var activationHandler: (() -> Void)?
    var rowMenuProvider: ((Int) -> NSMenu?)?
    var rowClickHandler: ((Int, NSEvent.ModifierFlags) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        if clickedRow >= 0, rowClickHandler?(clickedRow, event.modifierFlags) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            activationHandler?()
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else { return super.menu(for: event) }
        return rowMenuProvider?(clickedRow) ?? super.menu(for: event)
    }
}
