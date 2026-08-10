#ifndef CS_AUDIO_RING_BUFFER_H
#define CS_AUDIO_RING_BUFFER_H

#include <stdint.h>

typedef struct CSAudioRingBuffer CSAudioRingBuffer;
typedef struct CSAudioTransportEnvelope CSAudioTransportEnvelope;

CSAudioRingBuffer *cs_audio_ring_buffer_create(uint64_t capacity_frames);
void cs_audio_ring_buffer_destroy(CSAudioRingBuffer *buffer);
void cs_audio_ring_buffer_clear(CSAudioRingBuffer *buffer);

uint64_t cs_audio_ring_buffer_capacity_frames(const CSAudioRingBuffer *buffer);
uint64_t cs_audio_ring_buffer_buffered_frames(const CSAudioRingBuffer *buffer);
uint64_t cs_audio_ring_buffer_frames_read(const CSAudioRingBuffer *buffer);
uint64_t cs_audio_ring_buffer_frames_requested(const CSAudioRingBuffer *buffer);
uint64_t cs_audio_ring_buffer_underrun_count(const CSAudioRingBuffer *buffer);
uint64_t cs_audio_ring_buffer_clipped_sample_count(const CSAudioRingBuffer *buffer);

uint64_t cs_audio_ring_buffer_write_stereo(
    CSAudioRingBuffer *buffer,
    const float *left,
    const float *right,
    uint64_t frame_count
);

uint64_t cs_audio_ring_buffer_write_mono_from_stereo(
    CSAudioRingBuffer *buffer,
    const float *left,
    const float *right,
    uint64_t frame_count
);

uint64_t cs_audio_ring_buffer_read_stereo(
    CSAudioRingBuffer *buffer,
    float *left,
    float *right,
    uint64_t frame_count
);

CSAudioTransportEnvelope *cs_audio_transport_envelope_create(void);
void cs_audio_transport_envelope_destroy(CSAudioTransportEnvelope *envelope);
void cs_audio_transport_envelope_set(CSAudioTransportEnvelope *envelope, float gain);
void cs_audio_transport_envelope_ramp(
    CSAudioTransportEnvelope *envelope,
    float gain,
    uint64_t frame_count
);
uint64_t cs_audio_transport_envelope_remaining_frames(const CSAudioTransportEnvelope *envelope);
void cs_audio_transport_envelope_apply_stereo(
    CSAudioTransportEnvelope *envelope,
    float *left,
    float *right,
    uint64_t frame_count
);

#endif
