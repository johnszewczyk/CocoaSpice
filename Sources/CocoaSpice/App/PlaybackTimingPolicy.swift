import Foundation

enum PlaybackTimingPolicy {
    static func playbackPlan(
        metadata: TrackMetadata?,
        trackPathExtension: String?,
        longPlayEnabled: Bool,
        manualPreFadeSeconds: Int,
        fadeSeconds: Int
    ) -> PlaybackPlan {
        let supportedFormat = trackPathExtension.flatMap {
            PlaybackFormatRegistry.module(forPathExtension: $0)
        } != nil
        let preFadeSeconds: Int
        let usesNativeEnding: Bool

        if longPlayEnabled, supportedFormat {
            usesNativeEnding = false
            preFadeSeconds = max(1, manualPreFadeSeconds)
        } else {
            if let metadata {
                let nativeMilliseconds = nativePlaybackMilliseconds(for: metadata)
                if nativeMilliseconds > 0 {
                    usesNativeEnding = max(0, fadeSeconds) == 0
                    preFadeSeconds = max(1, Int(round(Double(nativeMilliseconds) / 1000.0)))
                } else {
                    usesNativeEnding = true
                    preFadeSeconds = 150
                }
            } else {
                usesNativeEnding = true
                preFadeSeconds = 150
            }
        }

        let clampedFadeSeconds = max(0, fadeSeconds)
        return PlaybackPlan(
            preFadeSeconds: preFadeSeconds,
            fadeSeconds: clampedFadeSeconds,
            totalSeconds: preFadeSeconds + clampedFadeSeconds,
            usesNativeEnding: usesNativeEnding,
            isLongPlay: longPlayEnabled && supportedFormat
        )
    }

    private static func nativePlaybackMilliseconds(for metadata: TrackMetadata) -> Int {
        if metadata.playLengthMs > 0 {
            return metadata.playLengthMs
        }

        if metadata.introLengthMs > 0 || metadata.loopLengthMs > 0 {
            return max(metadata.introLengthMs + metadata.loopLengthMs, metadata.loopLengthMs)
        }

        return 0
    }
}
