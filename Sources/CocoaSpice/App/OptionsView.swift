import AppKit
import SwiftUI

struct OptionsView: View {
    @Bindable var model: PlayerViewModel
    @State private var longPlayTimeText = ""
    @State private var selection: Section = .playback

    private enum Section: String, CaseIterable, Identifiable {
        case playback = "Playback"
        case interface = "Interface"
        case database = "Database"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .playback: "waveform"
            case .interface: "paintbrush"
            case .database: "externaldrive"
            }
        }
    }

    private let windowBackground = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    private let panelBackground = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Options")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(selection.rawValue)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selection {
                        case .playback: playbackPage
                        case .interface: interfacePage
                        case .database: databasePage
                        }
                    }
                    .padding(20)
                }

                if selection == .database {
                    Divider()
                    HStack {
                        Spacer()
                        if let libraryScanStatus = model.libraryScanStatus, !libraryScanStatus.isEmpty {
                            Text(libraryScanStatus)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button("Rescan Enabled Paths") { model.rescanEnabledLibraryRoots() }
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            longPlayTimeText = Self.formatTime(model.manualPreFadeSeconds)
        }
        .onDisappear {
            model.savePreferencesNow()
        }
        .onChange(of: model.manualPreFadeSeconds) { _, newValue in
            let formatted = Self.formatTime(newValue)
            if longPlayTimeText != formatted {
                longPlayTimeText = formatted
            }
        }
    }

    private var playbackPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Long Play") {
                HStack(spacing: 12) {
                    Toggle(isOn: $model.longPlayEnabled) {
                        Text("Enable extended playback")
                            .foregroundStyle(.white)
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: model.longPlayEnabled) { _, _ in
                        model.toggleLongPlayEnabled()
                    }

                    Spacer(minLength: 24)

                    TextField("0:00", text: $longPlayTimeText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .onSubmit(applyLongPlayTimeText)
                }

                Text("Set the target duration used when Long Play is enabled.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var interfacePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Spectrum") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose the colors used by the toolbar spectrum analyzer.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        ColorPicker("Base", selection: colorBinding(for: \.spectrumGradientStartColor), supportsOpacity: false)
                            .foregroundStyle(.white)
                        ColorPicker("Peak", selection: colorBinding(for: \.spectrumGradientEndColor), supportsOpacity: false)
                            .foregroundStyle(.white)
                        ColorPicker("Cap", selection: colorBinding(for: \.spectrumPeakColor), supportsOpacity: false)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private var databasePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Library Paths") {
                HStack(alignment: .firstTextBaseline) {
                    Spacer()
                    Button("Add Folders…") {
                        model.chooseLibraryScanRoots()
                    }
                }

                if model.libraryScanRoots.isEmpty {
                    Text("No scan roots configured.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.libraryScanRoots) { root in
                            scanRootRow(root)
                        }
                    }
                }
            }

            sectionCard(title: "Library Behavior") {
                Toggle(isOn: Binding(
                    get: { model.playlistFollowsCursor },
                    set: { model.setPlaylistFollowsCursorEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Playlist Follows Cursor")
                            .foregroundStyle(.white)
                        Text("Selecting a folder immediately replaces the current playlist with that folder.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { model.sidebarDoubleClickAction == .enqueue },
                    set: { model.sidebarDoubleClickAction = $0 ? .enqueue : .playNow }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Double-Click Enqueues")
                            .foregroundStyle(.white)
                        Text("Double-click only adds items to the playlist.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func colorBinding(for keyPath: ReferenceWritableKeyPath<PlayerViewModel, NSColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: model[keyPath: keyPath]) },
            set: { model[keyPath: keyPath] = NSColor($0) }
        )
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(panelBackground))
    }

    @ViewBuilder
    private func scanRootRow(_ root: LibraryScanRoot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { root.isEnabled },
                        set: { model.setLibraryScanRootEnabled(root.id, isEnabled: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)

                Text(model.libraryScanRootStatusText(root))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    Button("Rescan") { model.rescanLibraryRoot(root.id) }
                    Button("Up") { model.moveLibraryScanRootUp(root.id) }
                        .disabled(!model.canMoveLibraryScanRootUp(root.id))
                    Button("Down") { model.moveLibraryScanRootDown(root.id) }
                        .disabled(!model.canMoveLibraryScanRootDown(root.id))
                    Button("Remove") { model.removeLibraryScanRoot(root.id) }
                }
            }

            Text(root.path)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func applyLongPlayTimeText() {
        let trimmed = longPlayTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSeconds = Self.parseTime(trimmed) ?? model.manualPreFadeSeconds
        model.manualPreFadeSeconds = max(30, parsedSeconds)
        model.handleManualPlaySecondsChanged()
        longPlayTimeText = Self.formatTime(model.manualPreFadeSeconds)
    }

    private static func formatTime(_ totalSeconds: Int) -> String {
        let minutes = max(0, totalSeconds) / 60
        let seconds = max(0, totalSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func parseTime(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2,
           let minutes = Int(parts[0]),
           let seconds = Int(parts[1]),
           (0..<60).contains(seconds) {
            return (minutes * 60) + seconds
        }

        if let seconds = Int(value) {
            return seconds
        }

        return nil
    }
}
