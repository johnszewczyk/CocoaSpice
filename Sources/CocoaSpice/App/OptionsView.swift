import AppKit
import SwiftUI

struct OptionsView: View {
    @Bindable var model: PlayerViewModel
    @State private var longPlayTimeText = ""
    @State private var selection: OptionsSection = .library
    @State private var hasInitializedPresentation = false
    @State private var confirmsResetPaths = false
    @State private var confirmsResetDatabase = false

    private enum OptionsSection: String, CaseIterable, Identifiable {
        case audio = "Audio"
        case data = "Data"
        case interface = "Interface"
        case library = "Library"
        case playback = "Playback"
        case plugins = "Plugins"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .audio: "speaker.wave.2"
            case .data: "cylinder.split.1x2"
            case .interface: "paintbrush"
            case .library: "externaldrive"
            case .playback: "waveform"
            case .plugins: "puzzlepiece.extension"
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
                        case .audio: audioPage
                        case .data: dataPage
                        case .interface: interfacePage
                        case .library: libraryPage
                        case .playback: playbackPage
                        case .plugins: pluginsPage
                        }
                    }
                    .padding(20)
                }

            }
        }
        .frame(minWidth: 320, minHeight: 240)
        .background(OptionsWindowConfigurator())
        .onAppear {
            longPlayTimeText = Self.formatTime(model.manualPreFadeSeconds)
            DispatchQueue.main.async {
                NSApp.windows.first(where: { $0.title == "Options" })?.makeFirstResponder(nil)
            }
            guard !hasInitializedPresentation else { return }
            hasInitializedPresentation = true
            selection = .library
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
        .alert("Reset All Library Paths?", isPresented: $confirmsResetPaths) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Paths", role: .destructive) {
                model.resetLibraryPaths()
            }
        } message: {
            Text("This removes every configured scan path from the active library. Indexed data stays in the database and can be reused if a path is added again.")
        }
        .alert("Reset Database?", isPresented: $confirmsResetDatabase) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Database", role: .destructive) {
                model.purgeLibraryDatabase()
            }
        } message: {
            Text("This permanently removes all indexed tracks, metadata, scan inventory, and scan logs. Your configured library paths remain and can be scanned again.")
        }
    }

    private struct OptionsWindowConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let window = nsView.window else { return }
            window.minSize = NSSize(width: 320, height: 240)
            window.level = .floating
            window.setFrameAutosaveName("CocoaSpice.Options")
        }
    }

    private var playbackPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Long Play") {
                HStack(spacing: 12) {
                    Toggle(isOn: $model.longPlayEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable extended playback")
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

            }

            sectionCard(title: "End Fade") {
                Toggle(isOn: Binding(
                    get: { model.endFadeEnabled },
                    set: { model.setEndFadeEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable 6-second fade out")
                            .foregroundStyle(.white)
                        Text("Applies to metadata-timed playback and Long Play. Turning it off lets tracks use their native ending.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

            }

            libraryBehaviorCard

            sectionCard(title: "Playback Diagnostics") {
                diagnosticRow(
                    "Buffer",
                    "\(model.playbackDiagnostics.bufferedMilliseconds) ms • \(model.playbackDiagnostics.bufferPercent)%"
                )
                diagnosticRow("Output", model.playbackDiagnostics.outputHealth.rawValue.capitalized)
                diagnosticRow("Underruns", "\(model.playbackDiagnostics.underrunCount)")
                diagnosticRow("Source Clips", "\(model.playbackDiagnostics.clippedSampleCount)")

                Text("Output detects when the source node stops receiving render requests while CocoaSpice thinks it is playing. It cannot detect a Bluetooth radio, codec, or speaker failure after Core Audio. Counters reset for each new track.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var audioPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            appVolumeCard
            monoCard
            equalizerCard
        }
    }

    private var monoCard: some View {
        sectionCard(title: "Mono") {
            Toggle(isOn: Binding(
                get: { model.monoEnabled },
                set: { model.setMonoEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Mono")
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

    private var pluginsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "External Plugins and Software") {
                Text("This page currently lists the external decoders, emulators, and libraries used by CocoaSpice. It is an inventory only; plugin loading and configuration are not exposed here yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(Self.externalComponents) { component in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(component.name)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(component.version)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private struct ExternalComponent: Identifiable {
        let id = UUID()
        let name: String
        let version: String
    }

    private static let externalComponents = [
        ExternalComponent(name: "Game Music Emu / libgme", version: "0.6.5"),
        ExternalComponent(name: "libopenmpt", version: "0.8.7"),
        ExternalComponent(name: "libvgm", version: "vendored snapshot"),
        ExternalComponent(name: "vgmstream", version: "vendored snapshot"),
        ExternalComponent(name: "mGBA / Highly Complete", version: "vendored snapshot"),
        ExternalComponent(name: "lazyusf2", version: "vendored snapshot"),
        ExternalComponent(name: "2sf2wav", version: "vendored snapshot"),
        ExternalComponent(name: "psflib", version: "vendored snapshot")
    ]

    private var interfacePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Spectrum") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $model.spectrumEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Spectrum")
                            Text("Uses a 4,096-point FFT at 10 analyses per second, plus a 60 FPS direct bar/peak display. 10/20/40 means 1/2/4 bands per octave from 20 Hz–20.48 kHz. Spectrum is off by default.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                        .toggleStyle(.checkbox)

                    HStack {
                        Text("Bands")
                        Spacer()
                        Picker("Bands", selection: Binding(
                            get: { model.spectrumBandCount },
                            set: { model.setSpectrumBandCount($0) }
                        )) {
                            ForEach(SpectrumBandCount.supported, id: \.self) { bandCount in
                                Text("\(bandCount)").tag(bandCount)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .foregroundStyle(.white)
                    }

                    spectrumColorRow("Spectrum Base", selection: colorBinding(for: \.spectrumGradientStartColor))
                    spectrumColorRow("Spectrum Peak", selection: colorBinding(for: \.spectrumGradientEndColor))
                    spectrumColorRow("Spectrum Cap", selection: colorBinding(for: \.spectrumPeakColor))

                    HStack {
                        Spacer()
                        Button("Reset") {
                            model.resetSpectrumColors()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            interfaceAppearanceCard

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
                    VStack(alignment: .trailing, spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { Double(model.databaseSidebarDisclosureGapPoints) },
                                set: { model.setDatabaseSidebarDisclosureGapPoints(CGFloat($0)) }
                            ),
                            in: 0...16,
                            step: 1
                        )
                        .frame(width: 140)
                        Text("\(Int(model.databaseSidebarDisclosureGapPoints)) pt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            sectionCard(title: "Windows") {
                Text("Restore the default size and centered position for CocoaSpice windows.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Reset") {
                        NotificationCenter.default.post(name: .cocoaSpiceResetWindows, object: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var interfaceAppearanceCard: some View {
        sectionCard(title: "Interface Style") {
            Text("Controls text in both the database sidebar and playlist.")
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

    private var libraryPage: some View {
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

                HStack(spacing: 8) {
                    libraryActionButton("Add Path") {
                        model.chooseLibraryScanRoots()
                    }
                    .disabled(model.libraryScanInProgress)
                    Button {
                        model.toggleAllLibraryScanRootsEnabled()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .help("Enable All / Disable All")
                    .accessibilityLabel("Enable All / Disable All Paths")
                    .disabled(model.libraryScanInProgress || model.libraryScanRoots.isEmpty)
                    libraryActionButton("Reset Paths") {
                        confirmsResetPaths = true
                    }
                    .disabled(model.libraryScanInProgress || model.libraryScanRoots.isEmpty)
                    libraryActionButton("Scan All") {
                        model.rescanEnabledLibraryRoots()
                    }
                    .disabled(model.libraryScanRoots.allSatisfy { !$0.isEnabled })
                    libraryActionButton("Test Links") {
                        model.trimMissingLibrary()
                    }
                    .disabled(model.libraryScanInProgress)
                }
            }

            sectionCard(title: "Scanner Options") {
                Toggle(isOn: $model.forceLibraryScan) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deep Scan")
                        Text("Unzip, read metadata for all files.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                    .toggleStyle(.checkbox)
                    .disabled(model.libraryScanInProgress)
            }

            if let progress = model.libraryOperationProgress {
                sectionCard(title: "Scan Status") {
                    libraryOperationStatusField(
                        title: "Current Activity",
                        value: model.libraryScanStatus ?? "Preparing library operation…"
                    )
                    libraryOperationStatusField(
                        title: "File Path",
                        value: model.libraryScanCurrentPath ?? "Preparing library path…"
                    )
                    libraryOperationStatusField(
                        title: "File Name",
                        value: model.libraryScanCurrentFile ?? model.libraryScanStatus ?? "Preparing…"
                    )
                    libraryOperationProgressBar(progress)
                    Button(model.libraryOperationIsLinkTest ? "Cancel Test Links" : (model.queuedLibraryScanCount > 0 ? "Stop Scan + Clear Queue" : "Cancel Scan")) {
                        model.stopLibraryScan()
                    }
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        }
        .animation(.easeInOut(duration: 0.2), value: model.libraryOperationProgress != nil)
    }

    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Database") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Entries")
                        Text("\(model.databaseEntryCount) indexed tracks • \(model.unlinkedDatabaseEntryCount) unlinked tracks")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset Database") {
                        confirmsResetDatabase = true
                    }
                    .disabled(model.libraryScanInProgress || model.databaseEntryCount == 0)
                }

                Divider()

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unlinked Sources")
                        Text(model.deadLinkSummaryText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clean Unlinked") {
                        model.deleteDeadLinks()
                    }
                    .disabled(model.isDeletingDeadLinks || model.libraryScanInProgress || model.deadLinkCount == 0)
                }

                Text("The database retains file data even when files move on disk to speed up scans. One unlinked source can retain many tracks, so source and track counts need not match.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            sectionCard(title: "Cache") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Archive Cache")
                        Text(model.archiveCacheSummaryText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear Cache") {
                        model.clearArchiveCache()
                    }
                    .disabled(model.isClearingArchiveCache || model.libraryScanInProgress)
                }

                if model.libraryScanInProgress {
                    Text("Stop the library scan before clearing its archive cache.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            model.refreshArchiveCacheSummary()
            model.refreshDeadLinkSummary()
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
                    Text("Game-list selection replaces the playlist; Files view queues only on double-click or Return.")
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

    private var equalizerCard: some View {
        sectionCard(title: "Equalizer") {
            Toggle(isOn: $model.equalizerEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Equalizer")
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
                Text("App Volume")
                    .frame(width: 76, alignment: .leading)
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

    private func spectrumColorRow(_ label: String, selection: Binding<Color>) -> some View {
        HStack {
            Text(label)
            Spacer()
            ColorPicker(label, selection: selection, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("\(label) spectrum color")
        }
    }

    @ViewBuilder
    private func libraryOperationProgressBar(_ progress: LibraryScanProgress) -> some View {
        if progress.total == 0 {
            ProgressView()
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Library operation progress")
        } else {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Library operation progress")
        }
    }

    private func libraryOperationStatusField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func scanRootRow(_ root: LibraryScanRoot) -> some View {
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
                .disabled(model.libraryScanInProgress)

                scanRootStatusIcon(root)

                Text(abbreviatedPath(for: root))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .help(root.path)

                Spacer()

            HStack(spacing: 4) {
                Button { model.scanLibraryRoot(root.id) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help(root.isEnabled ? "Scan Path" : "Scan Path Without Enabling It")
                .disabled(model.libraryScanInProgress)
                Button { model.openLibraryScanLog(root.id) } label: {
                    Image(systemName: "doc.text")
                }
                .help("Open Scan Log")
                .disabled(!model.hasLibraryScanLog(root.id))
                Button(role: .destructive) { model.removeLibraryScanRoot(root.id) } label: {
                    Image(systemName: "trash")
                }
                .help("Remove Path")
                .disabled(model.libraryScanInProgress)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func libraryActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func scanRootStatusIcon(_ root: LibraryScanRoot) -> some View {
        if model.libraryScanRootIsEmpty(root) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Scan completed with no playable files")
        } else if model.libraryScanRootNeedsRescan(root) || model.libraryScanRootHasIssues(root) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.yellow)
                .accessibilityLabel("Scan completed with issues; see Log for details")
        } else if model.libraryScanRootIsClean(root) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Scan completed without issues")
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not yet scanned")
        }
    }

    private func abbreviatedPath(for root: LibraryScanRoot) -> String {
        let paths = model.libraryScanRoots.map { URL(fileURLWithPath: $0.path).pathComponents }
        guard let first = paths.first else { return root.path }
        let sharedCount = paths.dropFirst().reduce(first.count) { count, path in
            zip(first.prefix(count), path.prefix(count)).prefix { $0 == $1 }.count
        }
        let components = URL(fileURLWithPath: root.path).pathComponents
        let suffix = Array(components.dropFirst(min(sharedCount, components.count)))
        // A single root has no useful shared prefix. Keep two meaningful
        // folders rather than reducing it to one opaque basename.
        let visible = suffix.isEmpty ? Array(components.suffix(2)) : suffix
        return visible.joined(separator: "/")
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
