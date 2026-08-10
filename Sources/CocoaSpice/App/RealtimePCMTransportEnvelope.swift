import CPlaybackAudio
import Foundation

/// Atomic per-frame transport gain for the realtime render callback. This is
/// intentionally separate from the persisted app-volume policy.
final class RealtimePCMTransportEnvelope: @unchecked Sendable {
    private let rawEnvelope: OpaquePointer

    init() throws {
        guard let rawEnvelope = cs_audio_transport_envelope_create() else {
            throw RealtimePCMTransportEnvelopeError.allocationFailed
        }
        self.rawEnvelope = rawEnvelope
    }

    deinit {
        cs_audio_transport_envelope_destroy(rawEnvelope)
    }

    var remainingFrames: Int {
        Int(cs_audio_transport_envelope_remaining_frames(rawEnvelope))
    }

    func set(_ gain: Float) {
        cs_audio_transport_envelope_set(rawEnvelope, gain)
    }

    func ramp(to gain: Float, overFrames frameCount: Int) {
        cs_audio_transport_envelope_ramp(rawEnvelope, gain, UInt64(max(0, frameCount)))
    }

    func apply(left: UnsafeMutableBufferPointer<Float>, right: UnsafeMutableBufferPointer<Float>) {
        let frameCount = min(left.count, right.count)
        guard frameCount > 0,
              let leftBaseAddress = left.baseAddress,
              let rightBaseAddress = right.baseAddress else {
            return
        }
        cs_audio_transport_envelope_apply_stereo(
            rawEnvelope,
            leftBaseAddress,
            rightBaseAddress,
            UInt64(frameCount)
        )
    }
}

enum RealtimePCMTransportEnvelopeError: LocalizedError {
    case allocationFailed

    var errorDescription: String? {
        "The realtime transport envelope could not be allocated."
    }
}
