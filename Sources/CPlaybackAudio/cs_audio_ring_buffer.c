#include "cs_audio_ring_buffer.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct CSAudioRingBuffer {
    float *left;
    float *right;
    uint64_t capacity_frames;
    _Atomic uint64_t read_index;
    _Atomic uint64_t write_index;
    _Atomic uint64_t frames_read;
    _Atomic uint64_t frames_requested;
    _Atomic uint64_t underrun_count;
    _Atomic uint64_t clipped_sample_count;
};

CSAudioRingBuffer *cs_audio_ring_buffer_create(uint64_t capacity_frames) {
    if (capacity_frames == 0) {
        return NULL;
    }

    CSAudioRingBuffer *buffer = calloc(1, sizeof(*buffer));
    if (buffer == NULL) {
        return NULL;
    }

    buffer->left = calloc(capacity_frames, sizeof(float));
    buffer->right = calloc(capacity_frames, sizeof(float));
    if (buffer->left == NULL || buffer->right == NULL) {
        free(buffer->left);
        free(buffer->right);
        free(buffer);
        return NULL;
    }

    buffer->capacity_frames = capacity_frames;
    atomic_init(&buffer->read_index, 0);
    atomic_init(&buffer->write_index, 0);
    atomic_init(&buffer->frames_read, 0);
    atomic_init(&buffer->frames_requested, 0);
    atomic_init(&buffer->underrun_count, 0);
    atomic_init(&buffer->clipped_sample_count, 0);
    return buffer;
}

void cs_audio_ring_buffer_destroy(CSAudioRingBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }

    free(buffer->left);
    free(buffer->right);
    free(buffer);
}

void cs_audio_ring_buffer_clear(CSAudioRingBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }

    uint64_t write_index = atomic_load_explicit(&buffer->write_index, memory_order_relaxed);
    atomic_store_explicit(&buffer->read_index, write_index, memory_order_release);
    atomic_store_explicit(&buffer->frames_read, 0, memory_order_release);
    atomic_store_explicit(&buffer->frames_requested, 0, memory_order_release);
    atomic_store_explicit(&buffer->underrun_count, 0, memory_order_release);
    atomic_store_explicit(&buffer->clipped_sample_count, 0, memory_order_release);
}

uint64_t cs_audio_ring_buffer_capacity_frames(const CSAudioRingBuffer *buffer) {
    return buffer == NULL ? 0 : buffer->capacity_frames;
}

uint64_t cs_audio_ring_buffer_buffered_frames(const CSAudioRingBuffer *buffer) {
    if (buffer == NULL) {
        return 0;
    }

    uint64_t write_index = atomic_load_explicit(&buffer->write_index, memory_order_acquire);
    uint64_t read_index = atomic_load_explicit(&buffer->read_index, memory_order_acquire);
    return write_index - read_index;
}

uint64_t cs_audio_ring_buffer_frames_read(const CSAudioRingBuffer *buffer) {
    return buffer == NULL
        ? 0
        : atomic_load_explicit(&buffer->frames_read, memory_order_acquire);
}

uint64_t cs_audio_ring_buffer_frames_requested(const CSAudioRingBuffer *buffer) {
    return buffer == NULL
        ? 0
        : atomic_load_explicit(&buffer->frames_requested, memory_order_acquire);
}

uint64_t cs_audio_ring_buffer_underrun_count(const CSAudioRingBuffer *buffer) {
    return buffer == NULL
        ? 0
        : atomic_load_explicit(&buffer->underrun_count, memory_order_acquire);
}

uint64_t cs_audio_ring_buffer_clipped_sample_count(const CSAudioRingBuffer *buffer) {
    return buffer == NULL
        ? 0
        : atomic_load_explicit(&buffer->clipped_sample_count, memory_order_acquire);
}

uint64_t cs_audio_ring_buffer_write_stereo(
    CSAudioRingBuffer *buffer,
    const float *left,
    const float *right,
    uint64_t frame_count
) {
    if (buffer == NULL || left == NULL || right == NULL || frame_count == 0) {
        return 0;
    }

    uint64_t write_index = atomic_load_explicit(&buffer->write_index, memory_order_relaxed);
    uint64_t read_index = atomic_load_explicit(&buffer->read_index, memory_order_acquire);
    uint64_t available = buffer->capacity_frames - (write_index - read_index);
    uint64_t frames_to_write = frame_count < available ? frame_count : available;
    uint64_t clipped_samples = 0;

    for (uint64_t offset = 0; offset < frames_to_write; offset += 1) {
        uint64_t slot = (write_index + offset) % buffer->capacity_frames;
        float left_sample = left[offset];
        float right_sample = right[offset];
        if (left_sample > 1.0f || left_sample < -1.0f) {
            clipped_samples += 1;
        }
        if (right_sample > 1.0f || right_sample < -1.0f) {
            clipped_samples += 1;
        }
        buffer->left[slot] = left_sample;
        buffer->right[slot] = right_sample;
    }

    if (clipped_samples > 0) {
        atomic_fetch_add_explicit(&buffer->clipped_sample_count, clipped_samples, memory_order_relaxed);
    }

    atomic_store_explicit(
        &buffer->write_index,
        write_index + frames_to_write,
        memory_order_release
    );
    return frames_to_write;
}

uint64_t cs_audio_ring_buffer_write_mono_from_stereo(
    CSAudioRingBuffer *buffer,
    const float *left,
    const float *right,
    uint64_t frame_count
) {
    if (buffer == NULL || left == NULL || right == NULL || frame_count == 0) {
        return 0;
    }

    uint64_t write_index = atomic_load_explicit(&buffer->write_index, memory_order_relaxed);
    uint64_t read_index = atomic_load_explicit(&buffer->read_index, memory_order_acquire);
    uint64_t available = buffer->capacity_frames - (write_index - read_index);
    uint64_t frames_to_write = frame_count < available ? frame_count : available;
    uint64_t clipped_samples = 0;

    for (uint64_t offset = 0; offset < frames_to_write; offset += 1) {
        uint64_t slot = (write_index + offset) % buffer->capacity_frames;
        float mono_sample = (left[offset] + right[offset]) * 0.5f;
        if (mono_sample > 1.0f || mono_sample < -1.0f) {
            clipped_samples += 2;
        }
        buffer->left[slot] = mono_sample;
        buffer->right[slot] = mono_sample;
    }

    if (clipped_samples > 0) {
        atomic_fetch_add_explicit(&buffer->clipped_sample_count, clipped_samples, memory_order_relaxed);
    }

    atomic_store_explicit(
        &buffer->write_index,
        write_index + frames_to_write,
        memory_order_release
    );
    return frames_to_write;
}

uint64_t cs_audio_ring_buffer_read_stereo(
    CSAudioRingBuffer *buffer,
    float *left,
    float *right,
    uint64_t frame_count
) {
    if (buffer == NULL || left == NULL || right == NULL || frame_count == 0) {
        return 0;
    }

    atomic_fetch_add_explicit(&buffer->frames_requested, frame_count, memory_order_relaxed);

    uint64_t read_index = atomic_load_explicit(&buffer->read_index, memory_order_relaxed);
    uint64_t write_index = atomic_load_explicit(&buffer->write_index, memory_order_acquire);
    uint64_t available = write_index - read_index;
    uint64_t frames_to_read = frame_count < available ? frame_count : available;

    if (frames_to_read < frame_count) {
        atomic_fetch_add_explicit(&buffer->underrun_count, 1, memory_order_relaxed);
    }

    for (uint64_t offset = 0; offset < frames_to_read; offset += 1) {
        uint64_t slot = (read_index + offset) % buffer->capacity_frames;
        left[offset] = buffer->left[slot];
        right[offset] = buffer->right[slot];
    }

    // Clearing advances read_index to the current writer position. Do not let
    // an output callback that began before that transition publish its stale
    // read position afterwards: doing so would expose old PCM ahead of the
    // newly queued track. A failed compare-and-swap means clear won; report no
    // frames so the source node fills this callback with silence.
    uint64_t expected_read_index = read_index;
    if (!atomic_compare_exchange_strong_explicit(
            &buffer->read_index,
            &expected_read_index,
            read_index + frames_to_read,
            memory_order_release,
            memory_order_relaxed
        )) {
        return 0;
    }
    atomic_fetch_add_explicit(&buffer->frames_read, frames_to_read, memory_order_relaxed);
    return frames_to_read;
}
