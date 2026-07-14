import AppKit
import SwiftUI

struct OptionsView: View {
    @Bindable var model: PlayerViewModel
    @State private var longPlayTimeText = ""
    @State private var sidebarFontSizeText = "11"
    @State private var selection: OptionsSection = .database

    private enum OptionsSection: String, CaseIterable, Identifiable {
        case database = "Database"
        case interface = "Interface"
        case playback = "Playback"

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
            List(selection: $selection) {
                Section("Components") {
                    ForEach(OptionsSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
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

            }
        }
        .frame(width: 1280, height: 720)
        .onAppear {
            longPlayTimeText = Self.formatTime(model.manualPreFadeSeconds)
            sidebarFontSizeText = Self.formatFontSize(model.databaseSidebarFontSize)
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

            libraryBehaviorCard
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

            sectionCard(title: "Sidebar") {
                Text("Controls the game list text in the main database sidebar.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Font size (pt)")
                    Spacer()
                    TextField("12", text: $sidebarFontSizeText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .onSubmit(applySidebarFontSizeText)
                }

                HStack {
                    Text("Text color")
                    Spacer()
                    Picker("Text color", selection: Binding(
                        get: { model.databaseSidebarTextColor },
                        set: { model.setDatabaseSidebarTextColor($0) }
                    )) {
                        ForEach(PlayerViewModel.DatabaseSidebarTextColor.allCases) { color in
                            Text(color.title).tag(color)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 72, alignment: .trailing)
                }

                Toggle("System Mode", isOn: Binding(
                    get: { model.sidebarSystemMode },
                    set: { model.setSidebarSystemMode($0) }
                ))
                .help("Group the sidebar into expandable System → Game trees.")

                HStack {
                    Spacer()
                    Button("Reset") {
                        model.setDatabaseSidebarFontSize(12)
                        model.setDatabaseSidebarTextColor(.primary)
                        sidebarFontSizeText = "12"
                    }
                    .frame(width: 72, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var databasePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Library Paths") {
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

                HStack {
                    Button("Add Folders…") {
                        model.chooseLibraryScanRoots()
                    }
                    Button("Trim Missing") {
                        model.trimMissingLibrary()
                    }
                    .disabled(model.libraryScanInProgress)
                    Spacer()
                }

                if let progress = model.trimMissingProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trim Missing • \(progress.current) of \(progress.total) sources checked")
                            .font(.system(size: 12))
                        ProgressView(value: progress.fraction)
                            .progressViewStyle(.linear)
                        if let path = model.trimMissingCurrentPath {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let status = model.libraryScanStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        }
    }

    private var libraryBehaviorCard: some View {
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

                Text(root.path)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    Button("Scan") { model.scanLibraryRoot(root.id) }
                    Button("Retry") { model.retryFailedLibraryRoot(root.id) }
                    Button("Log") { model.openLibraryScanLog(root.id) }
                        .disabled(!model.hasLibraryScanLog(root.id))
                    Button("Del") { model.removeLibraryScanRoot(root.id) }
                }
            }

            HStack(spacing: 10) {
                Text(model.libraryScanRootDetailText(root))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let progress = model.libraryScanProgressFraction(for: root.id) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                } else {
                    Text(model.libraryScanRootStatusText(root))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if model.libraryScanRootIsEmpty(root) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .accessibilityLabel("Scan completed with no playable files")
                } else if model.libraryScanRootNeedsRescan(root) || model.libraryScanRootHasIssues(root) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Scan completed with issues; see Log for details")
                } else if model.libraryScanRootIsClean(root) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Scan completed without issues")
                }
            }
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

    private func applySidebarFontSizeText() {
        let parsed = Double(sidebarFontSizeText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 12
        guard parsed.isFinite else { return }
        model.setDatabaseSidebarFontSize(CGFloat(parsed))
        sidebarFontSizeText = Self.formatFontSize(model.databaseSidebarFontSize)
    }

    private static func formatFontSize(_ size: CGFloat) -> String {
        size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)
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
