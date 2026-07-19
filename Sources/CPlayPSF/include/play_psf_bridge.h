#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void* cocoaspice_play_psf_open(const char* path);
void cocoaspice_play_psf_close(void* handle);
int32_t cocoaspice_play_psf_read(void* handle, int16_t* interleavedStereo, int32_t frameCount);
int32_t cocoaspice_play_psf_seek(void* handle, int64_t frame);
void cocoaspice_play_psf_set_long_play(void* handle, int32_t enabled);
void cocoaspice_play_psf_set_suspended(void* handle, int32_t suspended);
int32_t cocoaspice_play_psf_finished(void* handle);
int64_t cocoaspice_play_psf_played_frames(void* handle);
int64_t cocoaspice_play_psf_play_length_frames(void* handle);
int64_t cocoaspice_play_psf_fade_length_frames(void* handle);
const char* cocoaspice_play_psf_tag(void* handle, const char* name);
const char* cocoaspice_play_psf_system_name(void* handle);
int64_t cocoaspice_play_psf_buffered_frames(void* handle);
int64_t cocoaspice_play_psf_buffer_capacity_frames(void);

void* cocoaspice_play_psf_metadata_open(const char* path);
void cocoaspice_play_psf_metadata_close(void* handle);
int64_t cocoaspice_play_psf_metadata_play_length_frames(void* handle);
int64_t cocoaspice_play_psf_metadata_fade_length_frames(void* handle);
const char* cocoaspice_play_psf_metadata_tag(void* handle, const char* name);
const char* cocoaspice_play_psf_metadata_system_name(void* handle);

#ifdef __cplusplus
}
#endif
