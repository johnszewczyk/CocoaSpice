import AppKit
import SwiftUI

struct AboutView: View {
    private let dependencies: [Dependency] = [
        Dependency(
            name: "game-music-emu / libgme",
            purpose: "SPC, NSF, GBS, HES, KSS, AY, SAP, and related formats",
            license: "LGPL-2.1-or-later",
            sourceURL: URL(string: "https://github.com/libgme/game-music-emu")!
        ),
        Dependency(
            name: "libvgm",
            purpose: "VGM, VGZ, GYM, and S98 formats",
            license: "Mixed upstream component licenses; see source notices",
            sourceURL: URL(string: "https://github.com/ValleyBell/libvgm")!
        ),
        Dependency(
            name: "mGBA",
            purpose: "Highly Complete GBA audio backend",
            license: "Mozilla Public License 2.0",
            sourceURL: URL(string: "https://github.com/mgba-emu/mgba")!
        ),
        Dependency(
            name: "psflib",
            purpose: "PSF-chain loading for GSF and USF-family formats",
            license: "See vendored source attribution",
            sourceURL: URL(string: "https://gitlab.com/kode54/psflib")!
        ),
        Dependency(
            name: "lazyusf2",
            purpose: "Nintendo 64 USF and miniUSF playback",
            license: "GNU General Public License 2.0-or-later",
            sourceURL: URL(string: "https://gitlab.com/kode54/lazyusf2")!
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
                                Link("Source", destination: dependency.sourceURL)
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
    let purpose: String
    let license: String
    let sourceURL: URL
}
