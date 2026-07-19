#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void* cocoaspice_psf2_open(const char* path);
void cocoaspice_psf2_close(void* handle);
int32_t cocoaspice_psf2_read(void* handle, int16_t* interleavedStereo, int32_t frameCount);
int32_t cocoaspice_psf2_seek(void* handle, int64_t frame);
void cocoaspice_psf2_set_long_play(void* handle, int32_t enabled);
void cocoaspice_psf2_set_suspended(void* handle, int32_t suspended);
int32_t cocoaspice_psf2_finished(void* handle);
int64_t cocoaspice_psf2_played_frames(void* handle);
int64_t cocoaspice_psf2_play_length_frames(void* handle);
const char* cocoaspice_psf2_tag(void* handle, const char* name);
int64_t cocoaspice_psf2_buffered_frames(void* handle);
int64_t cocoaspice_psf2_buffer_capacity_frames(void);

void* cocoaspice_psf2_metadata_open(const char* path);
void cocoaspice_psf2_metadata_close(void* handle);
int64_t cocoaspice_psf2_metadata_play_length_frames(void* handle);
const char* cocoaspice_psf2_metadata_tag(void* handle, const char* name);

#ifdef __cplusplus
}
#endif
