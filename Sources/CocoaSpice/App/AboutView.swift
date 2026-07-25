import AppKit
import SwiftUI

struct AboutView: View {
    private let dependencies: [Dependency] = [
        Dependency(
            name: "game-music-emu / libgme",
            version: "vendored source snapshot",
            purpose: "SPC, NSF, GBS, HES, KSS, AY, SAP, and related formats",
            license: "LGPL-2.1-or-later",
            sourceURL: URL(string: "https://github.com/libgme/game-music-emu")!,
            licenseURL: URL(string: "https://github.com/libgme/game-music-emu/blob/master/COPYING")!
        ),
        Dependency(
            name: "libopenmpt",
            version: "0.8.7",
            purpose: "FastTracker XM module playback",
            license: "BSD 3-Clause",
            sourceURL: URL(string: "https://lib.openmpt.org/libopenmpt/")!,
            licenseURL: URL(string: "https://github.com/OpenMPT/openmpt/blob/master/LICENSE")!
        ),
        Dependency(
            name: "libvgm",
            version: "0.1 / 867223e",
            purpose: "VGM, VGZ, GYM, and S98 formats",
            license: "Mixed upstream component licenses; see source notices",
            sourceURL: URL(string: "https://github.com/ValleyBell/libvgm")!,
            licenseURL: URL(string: "https://github.com/ValleyBell/libvgm/tree/master/licenses")!
        ),
        Dependency(
            name: "mGBA",
            version: "d49c093",
            purpose: "Highly Complete GBA audio backend",
            license: "Mozilla Public License 2.0",
            sourceURL: URL(string: "https://github.com/mgba-emu/mgba")!,
            licenseURL: URL(string: "https://github.com/mgba-emu/mgba/blob/master/LICENSE")!
        ),
        Dependency(
            name: "psflib",
            version: "vendored source snapshot",
            purpose: "PSF-chain loading for GSF and USF-family formats",
            license: "See vendored source attribution",
            sourceURL: URL(string: "https://gitlab.com/kode54/psflib")!,
            licenseURL: URL(string: "https://gitlab.com/kode54/psflib/-/blob/master/COPYING")!
        ),
        Dependency(
            name: "lazyusf2",
            version: "421f00b (2022-03-09)",
            purpose: "Nintendo 64 USF and miniUSF playback",
            license: "GNU General Public License 2.0-or-later",
            sourceURL: URL(string: "https://gitlab.com/kode54/lazyusf2")!,
            licenseURL: URL(string: "https://gitlab.com/kode54/lazyusf2/-/blob/master/COPYING")!
        ),
        Dependency(
            name: "vgmstream",
            version: "r2117 / 7f1ceb3",
            purpose: "PlayStation XA, PlayStation 2 streams, and other game-audio formats",
            license: "BSD-3-Clause and component licenses",
            sourceURL: URL(string: "https://github.com/vgmstream/vgmstream")!,
            licenseURL: URL(string: "https://github.com/vgmstream/vgmstream/blob/master/LICENSE")!
        ),
        Dependency(
            name: "2sf2wav",
            version: "vendored source snapshot",
            purpose: "Nintendo DS 2SF playback",
            license: "GNU General Public License 2.0-or-later",
            sourceURL: URL(string: "https://github.com/DeaDBeeF-Player/deadbeef/tree/master/plugins/2sf")!,
            licenseURL: URL(string: "https://github.com/DeaDBeeF-Player/deadbeef/blob/master/COPYING")!
        ),
        Dependency(
            name: "Play! PsfCore",
            version: "0.30 / 50aedca",
            purpose: "PlayStation PSF/miniPSF and PlayStation 2 PSF2/miniPSF2 emulation",
            license: "BSD 3-Clause",
            sourceURL: URL(string: "https://github.com/jpd002/Play-")!,
            licenseURL: URL(string: "https://github.com/jpd002/Play-/blob/master/License.txt")!
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if let icon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                }

                Text("CocoaSpice")
                    .font(.title.weight(.semibold))
                Text("Game-music player for macOS")
                    .foregroundStyle(.secondary)
                Text("Version \(versionString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("External Code")
                        .font(.headline)

                    Text("CocoaSpice embeds and links external open-source projects for format decoding and emulation. Their source, copyright, and license obligations remain applicable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(dependencies) { dependency in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(dependency.name)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(dependency.version)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Link("Source", destination: dependency.sourceURL)
                                    .font(.caption)
                                Link("License", destination: dependency.licenseURL)
                                    .font(.caption)
                            }
                            Text(dependency.purpose)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(dependency.license)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 4)
                    }

                    Divider()

                    Text("The complete third-party license notes are included with the CocoaSpice source distribution in THIRD_PARTY_LICENSES.md and alongside the vendored source trees.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(width: 560, height: 620)
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }
}

private struct Dependency: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    let purpose: String
    let license: String
    let sourceURL: URL
    let licenseURL: URL
}
