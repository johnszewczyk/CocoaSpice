import AppKit
import SwiftUI

struct MainView: View {
    @Bindable var model: PlayerViewModel
    private let enableNativeSearchFields = true

    var body: some View {
        liveMainView
        .frame(minWidth: 320, minHeight: 240)
        .background(WindowToolbarSpectrumAccessory(model: model.toolbarSpectrum))
        .toolbar {
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
        }
    }

    private var liveMainView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if enableNativeSearchFields {
                    NativeSearchField(
                        text: $model.sidebarSearchText,
                        placeholder: "Search Database",
                        debounceInterval: 0.02
                    )
                    .padding(.horizontal, 8)
                    .padding(.top, 0)
                    .padding(.bottom, 2)
                }

                Group {
                    if model.databaseGameItems.isEmpty {
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
                    } else if model.visibleDatabaseGameItems.isEmpty {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "magnifyingglass",
                            description: Text("No database games match the current sidebar search.")
                        )
                    } else {
                        DatabaseGameListView(model: model)
                    }
                }
            }
            .navigationSplitViewColumnWidth(ideal: 220, max: 500)
        } detail: {
            VStack(spacing: 0) {
                if enableNativeSearchFields {
                    NativeSearchField(text: $model.playlistSearchText, placeholder: "Search Queue")
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                }

                ZStack {
                    PlaylistTableView(model: model)

                    if model.playlist.isEmpty {
                        ContentUnavailableView("Empty Queue", systemImage: "music.note.list", description: Text("Double-click a game or a folder search result in the sidebar to queue tracks."))
                            .allowsHitTesting(false)
                    } else if model.visiblePlaylist.isEmpty {
                        ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("No queued tracks match the current filter."))
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

            Text(model.elapsedReadout)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
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

private struct DatabaseGameListView: NSViewRepresentable {
    @Bindable var model: PlayerViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = DatabaseGameNativeTableView(frame: .zero)
        tableView.headerView = nil
        tableView.rowHeight = 16
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .regular
        tableView.usesAutomaticRowHeights = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = true
        tableView.backgroundColor = .clear
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleAction(_:))
        tableView.target = context.coordinator
        tableView.activationHandler = { [weak coordinator = context.coordinator] in
            coordinator?.handleReturnActivation()
        }
        tableView.rowMenuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.makeRowMenu(clickedRow: row)
        }

        let column = NSTableColumn(identifier: .init("Game"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        context.coordinator.attach(tableView: tableView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.reload()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        @Bindable var model: PlayerViewModel
        private weak var tableView: DatabaseGameNativeTableView?

        init(model: PlayerViewModel) {
            self._model = Bindable(model)
        }

        func attach(tableView: DatabaseGameNativeTableView) {
            self.tableView = tableView
        }

        func reload() {
            guard let tableView else { return }
            tableView.reloadData()

            let rows = IndexSet(model.visibleDatabaseGameItems.enumerated().compactMap { index, item in
                model.selectedDatabaseGameIDs.contains(item.id) ? index : nil
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
            model.visibleDatabaseGameItems.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            16
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < model.visibleDatabaseGameItems.count else { return nil }
            let item = model.visibleDatabaseGameItems[row]
            let identifier = NSUserInterfaceItemIdentifier("DatabaseGameCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
                let cell = NSTableCellView()
                cell.identifier = identifier

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.font = .systemFont(ofSize: 11)
                textField.lineBreakMode = .byTruncatingTail
                textField.textColor = .secondaryLabelColor
                cell.textField = textField
                cell.addSubview(textField)

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])

                return cell
            }()

            cell.textField?.stringValue = item.displayName
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            let rows = tableView.selectedRowIndexes.filter { $0 >= 0 && $0 < model.visibleDatabaseGameItems.count }
            let ids = rows.map { model.visibleDatabaseGameItems[$0].id }
            let primaryID = rows.last.map { model.visibleDatabaseGameItems[$0].id }
            model.selectDatabaseGames(ids: ids, primaryID: primaryID)
            reloadVisibleRows()
        }

        @objc func handleDoubleAction(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < model.visibleDatabaseGameItems.count else { return }
            let item = model.visibleDatabaseGameItems[row]
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
            guard clickedRow >= 0, clickedRow < model.visibleDatabaseGameItems.count else { return nil }
            let item = model.visibleDatabaseGameItems[clickedRow]
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
            let rows = IndexSet(integersIn: 0..<tableView.numberOfRows)
            let columns = IndexSet(integersIn: 0..<tableView.numberOfColumns)
            tableView.reloadData(forRowIndexes: rows, columnIndexes: columns)
        }
    }
}

@MainActor
private final class DatabaseGameNativeTableView: NSTableView {
    var activationHandler: (() -> Void)?
    var rowMenuProvider: ((Int) -> NSMenu?)?

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
