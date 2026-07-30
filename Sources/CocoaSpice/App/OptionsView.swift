import AppKit
import SwiftUI

struct OptionsView: View {
    @Bindable var model: PlayerViewModel
    @State private var longPlayTimeText = ""
    @State private var selection: OptionsSection = .library

    private enum OptionsSection: String, CaseIterable, Identifiable {
        case library = "Library"
        case data = "Data"
        case interface = "Interface"
        case playback = "Playback"
        case plugins = "Plugins"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .playback: "waveform"
            case .interface: "paintbrush"
            case .library: "externaldrive"
            case .data: "cylinder.split.1x2"
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
                        case .playback: playbackPage
                        case .interface: interfacePage
                        case .library: libraryPage
                        case .data: dataPage
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
            model.refreshArchiveCacheSummary()
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

            appVolumeCard

            equalizerCard

            sectionCard(title: "Playback Diagnostics") {
                diagnosticRow(
                    "Buffer",
                    "\(model.playbackDiagnostics.bufferedMilliseconds) ms • \(model.playbackDiagnostics.bufferPercent)%"
                )
                diagnosticRow("Underruns", "\(model.playbackDiagnostics.underrunCount)")
                diagnosticRow("Source Clips", "\(model.playbackDiagnostics.clippedSampleCount)")

                Text("Counters reset for each new track. Source Clips counts PCM samples above full scale before macOS output; it cannot detect amplifier or speaker distortion.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
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
                Text("Uses a 4,096-point FFT at 10 analyses per second, plus a 45 FPS direct bar/peak display. 10/20/40 means 1/2/4 bands per octave from 20 Hz–20.48 kHz. 20/40 add detail and CPU work while playing; disable Spectrum to remove analyzer and display work.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Toggle("Enable Spectrum", isOn: $model.spectrumEnabled)
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.white)

                    Picker("Bands", selection: Binding(
                        get: { model.spectrumBandCount },
                        set: { model.setSpectrumBandCount($0) }
                    )) {
                        ForEach(SpectrumBandCount.supported, id: \.self) { bandCount in
                            Text("\(bandCount)").tag(bandCount)
                        }
                    }
                    .foregroundStyle(.white)

                    Divider()

                    Text("Spectrum Colors")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)

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

                HStack {
                    Text("Monospace Font")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.databaseSidebarMonospaceFont },
                        set: { model.setDatabaseSidebarMonospaceFont($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                }

                HStack {
                    Text("Group by Console")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.sidebarSystemMode },
                        set: { model.setSidebarSystemMode($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .help("Group the sidebar into expandable System → Game trees.")
                }

                HStack {
                    Spacer()
                    Button("Reset") {
                        model.setDatabaseSidebarFontSize(12)
                        model.setDatabaseSidebarTextColor(.primary)
                        model.setDatabaseSidebarMonospaceFont(false)
                        model.setSidebarSystemMode(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            sectionCard(title: "Playlist") {
                Text("Controls the editable track table in the main window.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Monospace Font")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.playlistMonospaceFont },
                        set: { model.setPlaylistMonospaceFont($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                }
            }

            sectionCard(title: "Windows") {
                Text("Restore the default size and centered position for CocoaSpice windows.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Reset Windows") {
                    NotificationCenter.default.post(name: .cocoaSpiceResetWindows, object: nil)
                }
            }
        }
    }

    private var libraryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Library Paths", accessory: {
                if let progress = model.libraryOperationProgress {
                    Group {
                        if progress.total == 0 {
                            ProgressView()
                        } else {
                            ProgressView(value: progress.fraction)
                        }
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 100)
                    .accessibilityLabel("Library operation progress")
                }
            }) {
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
                    libraryActionButton("Reset Paths") {
                        model.resetLibraryPaths()
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
                    if model.libraryScanInProgress {
                        libraryActionButton(model.queuedLibraryScanCount > 0 ? "Stop + Clear Queue" : "Stop") {
                            model.stopLibraryScan()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Deep Scan", isOn: $model.forceLibraryScan)
                        .toggleStyle(.checkbox)
                        .disabled(model.libraryScanInProgress)
                    Text("Unzip, read metadata for all files.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

            }

        }
    }

    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: "Database") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Entries")
                        Text("\(model.databaseEntryCount) indexed tracks • \(model.unlinkedDatabaseEntryCount) unlinked")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear Database") {
                        model.purgeLibraryDatabase()
                    }
                    .disabled(model.libraryScanInProgress || model.databaseEntryCount == 0)
                }

                Divider()

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dead Links")
                        Text(model.deadLinkSummaryText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clean Links") {
                        model.deleteDeadLinks()
                    }
                    .disabled(model.isDeletingDeadLinks || model.libraryScanInProgress || model.deadLinkCount == 0)
                }

                Text("The database retains file data even when files move on disk to speed up scans.")
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
            Toggle("Enable Equalizer", isOn: $model.equalizerEnabled)
                .toggleStyle(.checkbox)
                .foregroundStyle(.white)

            Text("Ten parametric bands apply to every playback format.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

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
            HStack(spacing: 8) {
                Text("App Volume")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
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

            Text("Applies to CocoaSpice playback only. Volume keys control macOS system volume.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
                .help("Scan Path")
                .disabled(!root.isEnabled)
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
