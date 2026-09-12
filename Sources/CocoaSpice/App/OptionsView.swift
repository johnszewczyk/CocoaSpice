import AppKit
import ArchiveCacheCore
import FavoriteStoreCore
import FrontendPreferencesCore
import SwiftUI
import VGMBoyKit

struct OptionsView: View {
    @Bindable var model: PlayerViewModel
    @State private var longPlayTimeText = ""
    @State private var unknownDurationTimeText = ""
    @State private var fadeTimeText = ""
    @State private var libGmeTempoText = PlaybackTempo.defaultValue.displayString
    @State private var libVgmTempoText = PlaybackTempo.defaultValue.displayString
    @State private var selection: OptionsSection = .data
    @State private var hasInitializedPresentation = false

    private enum OptionsSection: String, CaseIterable, Identifiable {
        case audio = "Audio"
        case data = "Database"
        case diagnostics = "Diagnostics"
        case interface = "Interface"
        case playback = "Playback"
        case windows = "Windows"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .audio: "speaker.wave.2"
            case .data: "cylinder.split.1x2"
            case .diagnostics: "waveform.path.ecg"
            case .interface: "paintbrush"
            case .playback: "waveform"
            case .windows: "macwindow.on.rectangle"
            }
        }
    }

    private static let appSections: [OptionsSection] = FrontendOptionsManifest.v1.appSections.compactMap {
        OptionsSection(rawValue: $0.title)
    }
    private static let remoteSections: [OptionsSection] = [.audio, .diagnostics, .playback]

    private var pageTitle: String {
        let owner = Self.remoteSections.contains(selection) ? "VGMBoy" : "CocoaSpice"
        return "\(owner) / \(selection.rawValue)"
    }

    private let windowBackground = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    private let panelBackground = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("CocoaSpice") {
                    ForEach(Self.appSections) { section in
                        Label(section.rawValue, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                Section("VGMBoy") {
                    ForEach(Self.remoteSections) { section in
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
                    Text(pageTitle)
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
                        case .audio: audioPage
                        case .data: dataPage
                        case .diagnostics: diagnosticsPage
                        case .interface: interfacePage
                        case .playback: playbackPage
                        case .windows: CocoaSpiceWindowsOptionsPage(model: model)
                        }
                    }
                    .padding(20)
                }

            }
        }
        .frame(minWidth: 320, minHeight: 240)
        .background(OptionsWindowConfigurator(alwaysOnTop: model.settingsWindowAlwaysOnTop))
        .onAppear {
            longPlayTimeText = Self.formatTime(model.manualPreFadeSeconds)
            unknownDurationTimeText = Self.formatTime(model.unknownDurationSeconds)
            fadeTimeText = Self.formatTime(model.configuredFadeSeconds)
            libGmeTempoText = model.libgmeTempo.displayString
            libVgmTempoText = model.libvgmTempo.displayString
            DispatchQueue.main.async {
                NSApp.windows.first(where: { $0.cocoaSpiceRole == .settings })?.makeFirstResponder(nil)
            }
            guard !hasInitializedPresentation else { return }
            hasInitializedPresentation = true
            selection = .data
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
        .onChange(of: model.unknownDurationSeconds) { _, newValue in
            let formatted = Self.formatTime(newValue)
            if unknownDurationTimeText != formatted {
                unknownDurationTimeText = formatted
            }
        }
        .onChange(of: model.configuredFadeSeconds) { _, newValue in
            let formatted = Self.formatTime(newValue)
            if fadeTimeText != formatted {
                fadeTimeText = formatted
            }
        }
    }

    private struct OptionsWindowConfigurator: NSViewRepresentable {
        let alwaysOnTop: Bool
        func makeNSView(context: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let window = nsView.window else { return }
            window.cocoaSpiceRole = .settings
            window.minSize = NSSize(width: 320, height: 240)
            window.level = alwaysOnTop ? .floating : .normal
            window.setFrameAutosaveName("CocoaSpice.Options")
        }
    }

    private var playbackPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Long Play") {
                HStack(spacing: 12) {
                    Toggle(isOn: $model.longPlayEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Extended playback")
                                .foregroundStyle(.white)
                            Text("Set the target duration used when Long Play is enabled.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
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

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unknown-length default")
                            .foregroundStyle(.white)
                        Text("Used when a decoder provides no natural duration and Long Play is off.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 24)

                    TextField("0:00", text: $unknownDurationTimeText)
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
                        .onSubmit(applyUnknownDurationTimeText)
                }

            }

            sectionCard(title: "End Fade") {
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { model.endFadeEnabled },
                        set: { model.setEndFadeEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fade Out")
                                .foregroundStyle(.white)
                            Text("Applies to metadata-timed playback and Long Play. Turning it off lets tracks use their native ending.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Spacer(minLength: 24)

                    TextField("0:06", text: $fadeTimeText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .onSubmit(applyFadeTimeText)
                }

                Toggle(isOn: Binding(
                    get: { model.fadedSkipEnabled },
                    set: { model.setFadedSkipEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Faded Skip")
                            .foregroundStyle(.white)
                        Text("Next and Previous fade the live track for the configured 6-second fade out before advancing. Press again to skip immediately.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

            }

            tempoCard

        }
    }

    private var diagnosticsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Buffer") {
                diagnosticRow(
                    "Buffer",
                    "\(model.playbackDiagnostics.bufferedMilliseconds) ms • \(model.playbackDiagnostics.bufferPercent)%"
                )
                diagnosticRow("Source Clips", "\(model.playbackDiagnostics.clippedSampleCount)")
            }
            sectionCard(title: "Decoder") {
                diagnosticRow("Decoder", model.playbackDiagnostics.decoderFamily ?? "—")
                diagnosticRow(
                    "Rates",
                    "\(model.playbackDiagnostics.decoderSampleRate) / \(model.playbackDiagnostics.sampleRate) Hz"
                )
                diagnosticRow(
                    "Decoded / Audible",
                    "\(model.playbackDiagnostics.decodedFrames) / \(model.playbackDiagnostics.audiblePositionFrames) frames"
                )
                diagnosticRow(
                    "Tempo",
                    "\(model.playbackDiagnostics.tempo.formatted(.number.precision(.fractionLength(3))))×"
                )
                Text("Output detects when the source node stops receiving render requests while CocoaSpice thinks it is playing. It cannot detect a Bluetooth radio, codec, or speaker failure after Core Audio. Counters reset for each new track.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            sectionCard(title: "Transport") {
                diagnosticRow("Output", model.playbackDiagnostics.outputHealth.rawValue.capitalized)
                diagnosticRow("Underruns", "\(model.playbackDiagnostics.underrunCount)")
            }
        }
    }

    private var tempoCard: some View {
        sectionCard(title: "Play Speed") {
            Text("Fractions and decimals are accepted and snap to 1/32 increments.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            tempoRow(
                title: "libgme",
                detail: "SPC, NSF/NSFE, GBS, HES, KSS, AY, and SAP",
                enabled: Binding(
                    get: { model.libgmeTempoEnabled },
                    set: { model.setLibGmeTempoEnabled($0) }
                ),
                text: $libGmeTempoText,
                commit: { commitTempo(libGmeTempoText, backend: .libgme) }
            )
            tempoRow(
                title: "libvgm",
                detail: "GYM, S98, VGM, VGZ, and DRO",
                enabled: Binding(
                    get: { model.libvgmTempoEnabled },
                    set: { model.setLibVgmTempoEnabled($0) }
                ),
                text: $libVgmTempoText,
                commit: { commitTempo(libVgmTempoText, backend: .libvgm) }
            )
        }
    }

    private enum TempoBackend {
        case libgme
        case libvgm
    }

    private func tempoRow(
        title: String,
        detail: String,
        enabled: Binding<Bool>,
        text: Binding<String>,
        commit: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: enabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("1", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .onSubmit(commit)
        }
    }

    private func commitTempo(_ rawValue: String, backend: TempoBackend) {
        guard let tempo = PlaybackTempo.parse(rawValue) else {
            switch backend {
            case .libgme: libGmeTempoText = model.libgmeTempo.displayString
            case .libvgm: libVgmTempoText = model.libvgmTempo.displayString
            }
            return
        }
        switch backend {
        case .libgme:
            libGmeTempoText = tempo.displayString
            model.setLibGmeTempo(tempo)
        case .libvgm:
            libVgmTempoText = tempo.displayString
            model.setLibVgmTempo(tempo)
        }
    }

    private var audioPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "AAC Export") {
                Text("Export Folder")
                pathBar(path: model.aacExportDirectoryPath, browse: model.chooseAACExportDirectory)
                Text("Playlist Export AAC writes a finite VGMBoy render here. New installs default to Downloads.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            equalizerCard
            monoCard
            appVolumeCard
        }
    }

    private var monoCard: some View {
        sectionCard(title: "Mono") {
            Toggle(isOn: Binding(
                get: { model.monoEnabled },
                set: { model.setMonoEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mono")
                    Text("Mix left and right channels, then play the same signal through both speakers.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var interfacePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            CocoaSpiceAnimationOptionsCard(model: model)
            interfaceAppearanceCard

            sectionCard(title: "Playlist Options") {
                Toggle(isOn: Binding(
                    get: { model.columnAutoSizeEnabled },
                    set: { model.setColumnAutoSizeEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Column Auto-size")
                        Text("Automatically resize columns for content width on selection.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            sectionCard(title: "Sidebar Options") {
                Toggle(isOn: Binding(
                        get: { model.sidebarSystemMode },
                        set: { model.setSidebarSystemMode($0) }
                    )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Group by Console")
                        Text("Sort game list into consoles using metadata and parent folders in Database view.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { model.preferFoldersOverMetadata },
                    set: { model.setPreferFoldersOverMetadata($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prefer Folders over Metadatas")
                        Text("Use the scanned archive or file's parent console folder before embedded console metadata when grouping games.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { model.databaseSidebarHidesFileExtensions },
                    set: { model.setDatabaseSidebarHidesFileExtensions($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide File Extensions")
                        Text("Hide extensions in Files view without changing the scanned filename or playback path.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files Disclosure Gap")
                        Text("Space between folder triangles and names in Files view, measured in points.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    TextField(
                        "6",
                        value: Binding(
                            get: { Double(model.databaseSidebarDisclosureGapPoints) },
                            set: { model.setDatabaseSidebarDisclosureGapPoints(CGFloat($0)) }
                        ),
                        format: .number.precision(.fractionLength(0))
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files Child Indent")
                        Text("Extra indent for each Files-view child level, measured in points. Default 8 pt is roughly one character at the default font size.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    TextField(
                        "8",
                        value: Binding(
                            get: { Double(model.databaseSidebarChildIndentPoints) },
                            set: { model.setDatabaseSidebarChildIndentPoints(CGFloat($0)) }
                        ),
                        format: .number.precision(.fractionLength(0))
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                }
            }

            libraryBehaviorCard
        }
    }

    private var interfaceAppearanceCard: some View {
        sectionCard(title: "Interface Style") {
            Text("Controls text, selection highlights, and active controls throughout both the database sidebar and playlist.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Text("Font Size")
                Spacer()
                Picker("Font Size", selection: Binding(
                    get: { Int(model.databaseSidebarFontSize) },
                    set: { model.setDatabaseSidebarFontSize(CGFloat($0)) }
                )) {
                    ForEach(6...18, id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack {
                Text("Font Color")
                Spacer()
                Picker("Font Color", selection: Binding(
                    get: { model.databaseSidebarTextColor },
                    set: { model.setDatabaseSidebarTextColor($0) }
                )) {
                    ForEach(PlayerViewModel.DatabaseSidebarTextColor.allCases) { color in
                        Text(color.title).tag(color)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Toggle(isOn: Binding(
                    get: { model.databaseSidebarMonospaceFont },
                    set: { model.setDatabaseSidebarMonospaceFont($0) }
                )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monospace Font")
                    Text("Use system fixed-width font in Sidebar and Playlist.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Reset") {
                    model.setDatabaseSidebarFontSize(12)
                    model.setDatabaseSidebarTextColor(.primary)
                    model.setDatabaseSidebarMonospaceFont(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Cache") {
                pathBar(path: ZipArchiveSupport.cacheDirectoryURL.path, browse: model.showArchiveCacheInFinder)
                HStack(alignment: .center, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { model.archiveCachePolicy.isEnabled },
                        set: { model.setArchiveCacheEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Cache")
                            Text("Decompressed files can be retained to reduce load time.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("Usage: \(model.archiveCacheSummaryText)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 12)
                    Picker("", selection: Binding(
                        get: { model.archiveCachePolicy.maximumBytes },
                        set: { model.setArchiveCacheLimitBytes($0) }
                    )) {
                        ForEach(ArchiveCachePolicy.supportedLimits, id: \.self) { bytes in
                            Text(ArchiveCachePolicy.displayLimit(bytes)).tag(bytes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!model.archiveCachePolicy.isEnabled)
                }

                HStack(spacing: 8) {
                    fullWidthActionButton("Use Default") {
                        model.setArchiveCacheEnabled(true)
                        model.setArchiveCacheLimitBytes(ArchiveCachePolicy.defaultLimitBytes)
                    }
                    fullWidthActionButton("Clear Cache") { model.clearArchiveCache() }
                        .disabled(model.isClearingArchiveCache)
                    fullWidthActionButton("Show in Finder") { model.showArchiveCacheInFinder() }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            sectionCard(title: "Database") {
                pathBar(path: model.configuredLibraryDatabasePath, browse: model.chooseLibraryDatabase)

                if let status = model.libraryDatabaseLocationStatus {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(status.hasPrefix("Database not selected") ? .red : .secondary)
                } else {
                    Text("CocoaSpice reads this schema-23 catalog. ScanSong owns scan paths, scanning, link checks, and cleanup.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    fullWidthActionButton("Use Default") { model.useDefaultLibraryDatabase() }
                    fullWidthActionButton("Reload Library") { model.reloadLibrary() }
                    fullWidthActionButton("Show in Finder") { model.showLibraryDatabaseInFinder() }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.localBrowserEnabled)
            .opacity(model.localBrowserEnabled ? 0.55 : 1)

            sectionCard(title: "Favorites") {
                Toggle(isOn: Binding(
                    get: { model.favoriteSortOrder == .historical },
                    set: { model.setFavoriteSortOrder($0 ? .historical : .alphabetical) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sort by Date Added")
                        Text("Sort favorites playlist by date added.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            sectionCard(title: "Local Files") {
                Toggle(isOn: Binding(
                    get: { model.localBrowserEnabled },
                    set: { model.setLocalBrowserEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Use Local Files")
                        Text("Browse one folder directly. The database library is disabled while this is on.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                pathBar(
                    path: model.localBrowserPath.isEmpty ? "No local folder selected" : model.localBrowserPath,
                    browse: model.chooseLocalBrowserRoot
                )
            }
        }
        .onAppear {
            model.refreshArchiveCacheSummary()
        }
    }

    private func pathBar(path: String, browse: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: browse) {
                Image(systemName: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Browse")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func fullWidthActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 24)
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
                    Text("Game-list selection replaces the playlist; multi-track and archive Files selections populate it, while single-track files require double-click or Return.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { model.sidebarDoubleClickAction == .enqueue },
                set: { model.setSidebarDoubleClickAction($0 ? .enqueue : .playNow) }
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

    private var equalizerCard: some View {
        sectionCard(title: "Equalizer") {
            Toggle(isOn: Binding(
                get: { model.equalizerEnabled },
                set: { model.setEqualizerEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Equalizer")
                        .foregroundStyle(.white)
                    Text("Ten parametric bands apply to every playback format.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
                .toggleStyle(.checkbox)

            VStack(spacing: 10) {
                ForEach(Array(AudioEqualizer.bandFrequencies.indices), id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(Self.equalizerBandLabel(for: AudioEqualizer.bandFrequencies[index]))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                        Slider(
                            value: Binding(
                                get: { Double(model.equalizerBandGains[index]) },
                                set: { model.setEqualizerBandGain(Float($0), at: index) }
                            ),
                            in: Double(AudioEqualizer.gainRange.lowerBound)...Double(AudioEqualizer.gainRange.upperBound),
                            step: 0.5
                        )
                        Text(String(format: "%+.1f", model.equalizerBandGains[index]))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Reset") { model.resetEqualizer() }
            }
        }
    }

    private var appVolumeCard: some View {
        sectionCard(title: "Volume") {
            Text("Applies to CocoaSpice playback only. Volume keys control macOS system volume.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(model.appVolume) },
                        set: { model.setAppVolume(Float($0)) }
                    ),
                    in: Double(AudioOutputVolume.range.lowerBound)...Double(AudioOutputVolume.range.upperBound),
                    step: 0.01
                )
                Text("\(Int((model.appVolume * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
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
        sectionCard(title: title, accessory: { EmptyView() }, content: content)
    }

    private func sectionCard<Content: View, Accessory: View>(
        title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 12)
                accessory()
            }
            Divider()
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(panelBackground))
    }

    private func applyLongPlayTimeText() {
        let trimmed = longPlayTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSeconds = Self.parseTime(trimmed) ?? model.manualPreFadeSeconds
        model.manualPreFadeSeconds = max(30, parsedSeconds)
        model.handleManualPlaySecondsChanged()
        longPlayTimeText = Self.formatTime(model.manualPreFadeSeconds)
    }

    private func applyUnknownDurationTimeText() {
        let trimmed = unknownDurationTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSeconds = Self.parseTime(trimmed) ?? model.unknownDurationSeconds
        model.setUnknownDurationSeconds(parsedSeconds)
        unknownDurationTimeText = Self.formatTime(model.unknownDurationSeconds)
    }

    private func applyFadeTimeText() {
        let trimmed = fadeTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSeconds = Self.parseTime(trimmed) ?? model.configuredFadeSeconds
        model.setFadeSeconds(parsedSeconds)
        fadeTimeText = Self.formatTime(model.configuredFadeSeconds)
    }

    private static func formatTime(_ totalSeconds: Int) -> String {
        let minutes = max(0, totalSeconds) / 60
        let seconds = max(0, totalSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func equalizerBandLabel(for frequency: Float) -> String {
        frequency >= 1_000
            ? "\(Int(frequency / 1_000))k"
            : "\(Int(frequency))"
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

private struct CocoaSpiceAnimationOptionsCard: View {
    @Bindable var model: PlayerViewModel

    var body: some View {
        optionsCard(title: "Animations") {
            timingRow(title: "Auto-Resize", detail: "Duration for automatic playlist column resizing (ms).", enabled: Binding(
                get: { model.autoResizeAnimationEnabled },
                set: { model.setAutoResizeAnimationEnabled($0) }
            ), value: Binding(
                get: { model.autoResizeAnimationMilliseconds },
                set: { model.setAutoResizeAnimationMilliseconds($0) }
            ))
            timingRow(title: "Selection Bar", detail: "Duration for playlist and sidebar selection movement (ms).", enabled: Binding(
                get: { model.selectionAnimationEnabled },
                set: { model.setSelectionAnimationEnabled($0) }
            ), value: Binding(
                get: { model.selectionAnimationMilliseconds },
                set: { model.setSelectionAnimationMilliseconds($0) }
            ))
        }
    }

    private func timingRow(title: String, detail: String, enabled: Binding<Bool>, value: Binding<Int>) -> some View {
        HStack {
            Toggle(isOn: enabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 16)
            TextField("200", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .disabled(!enabled.wrappedValue)
        }
    }
}

private struct CocoaSpiceWindowsOptionsPage: View {
    @Bindable var model: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            optionsCard(title: "Always on Top") {
                windowToggle(
                    title: "Main Window",
                    detail: "Keep main window on top of other apps.",
                    isOn: Binding(get: { model.mainWindowAlwaysOnTop }, set: { model.setMainWindowAlwaysOnTop($0) })
                )
                windowToggle(
                    title: "Options Window",
                    detail: "Keep options window on top of main window.",
                    isOn: Binding(get: { model.settingsWindowAlwaysOnTop }, set: { model.setSettingsWindowAlwaysOnTop($0) })
                )
            }
            optionsCard(title: "Window Layout") {
                Text("Restore the default size and centered position for CocoaSpice windows.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Spacer(); Button("Reset") { NotificationCenter.default.post(name: .cocoaSpiceResetWindows, object: nil) } }
            }
        }
    }

    private func windowToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}

private func optionsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        Text(title).font(.headline).foregroundStyle(.white)
        Divider()
        content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)))
}
