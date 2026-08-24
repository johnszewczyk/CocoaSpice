import Foundation
import VGMBoyKit

typealias PlaybackPlan = PlaybackTimingPlan

enum PlaybackTimingPolicy {
    static func playbackPlan(
        metadata: TrackMetadata?,
        trackPathExtension: String?,
        longPlayEnabled: Bool,
        manualPreFadeSeconds: Int,
        fadeSeconds: Int,
        unknownDurationSeconds: Int = PlaybackTimingPreferences.defaultUnknownDurationSeconds
    ) -> PlaybackPlan {
        let family = trackPathExtension.flatMap {
            FormatRegistry.family(for: "source.\($0)")
        }
        return VGMBoyKit.PlaybackTimingPolicy.plan(
            metadata: metadata?.playbackTimingMetadata,
            family: family,
            longPlayEnabled: longPlayEnabled,
            preferences: PlaybackTimingPreferences(
                longPlaySeconds: manualPreFadeSeconds,
                unknownDurationSeconds: unknownDurationSeconds,
                fadeSeconds: fadeSeconds
            )
        )
    }
}
