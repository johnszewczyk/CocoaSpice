import CPlaybackAudio
import Foundation

final class RealtimePCMFrameRingBuffer: @unchecked Sendable {
    private let rawBuffer: OpaquePointer

    init(capacityFrames: Int) throws {
        guard capacityFrames > 0,
              let rawBuffer = cs_audio_ring_buffer_create(UInt64(capacityFrames)) else {
            throw RealtimePCMFrameRingBufferError.invalidCapacity
        }
        self.rawBuffer = rawBuffer
    }

    deinit {
        cs_audio_ring_buffer_destroy(rawBuffer)
    }

    var capacityFrames: Int {
        Int(cs_audio_ring_buffer_capacity_frames(rawBuffer))
    }

    var bufferedFrames: Int {
        Int(cs_audio_ring_buffer_buffered_frames(rawBuffer))
    }

    var framesRead: Int64 {
        Int64(cs_audio_ring_buffer_frames_read(rawBuffer))
    }

    var framesRequested: Int64 {
        Int64(cs_audio_ring_buffer_frames_requested(rawBuffer))
    }

    var underrunCount: Int64 {
        Int64(cs_audio_ring_buffer_underrun_count(rawBuffer))
    }

    func clear() {
        cs_audio_ring_buffer_clear(rawBuffer)
    }

    func write(left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>) -> Int {
        let frameCount = min(left.count, right.count)
        guard frameCount > 0,
              let leftBaseAddress = left.baseAddress,
              let rightBaseAddress = right.baseAddress else {
            return 0
        }

        return Int(cs_audio_ring_buffer_write_stereo(
            rawBuffer,
            leftBaseAddress,
            rightBaseAddress,
            UInt64(frameCount)
        ))
    }

    func read(
        left: UnsafeMutableBufferPointer<Float>,
        right: UnsafeMutableBufferPointer<Float>
    ) -> Int {
        let frameCount = min(left.count, right.count)
        guard frameCount > 0,
              let leftBaseAddress = left.baseAddress,
              let rightBaseAddress = right.baseAddress else {
            return 0
        }

        return Int(cs_audio_ring_buffer_read_stereo(
            rawBuffer,
            leftBaseAddress,
            rightBaseAddress,
            UInt64(frameCount)
        ))
    }
}

enum RealtimePCMFrameRingBufferError: LocalizedError {
    case invalidCapacity

    var errorDescription: String? {
        "The realtime audio ring buffer requires a positive frame capacity."
    }
}
