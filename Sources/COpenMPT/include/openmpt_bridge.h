#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *openmpt_player_handle_t;

typedef struct {
    char *title;
    char *artist;
    char *tracker;
    int32_t play_length_ms;
} openmpt_metadata_t;

openmpt_player_handle_t openmpt_player_create(const char *path, int32_t sample_rate, char **error_message);
void openmpt_player_destroy(openmpt_player_handle_t handle);
int32_t openmpt_inspect_file(const char *path, openmpt_metadata_t *metadata, char **error_message);
int32_t openmpt_player_read_metadata(openmpt_player_handle_t handle, openmpt_metadata_t *metadata, char **error_message);
int32_t openmpt_player_set_long_play(openmpt_player_handle_t handle, int32_t enabled, char **error_message);
int32_t openmpt_player_seek_milliseconds(openmpt_player_handle_t handle, int32_t milliseconds, char **error_message);
int32_t openmpt_player_render_s16(openmpt_player_handle_t handle, int32_t requested_frames, int16_t *samples, int32_t *rendered_frames, char **error_message);
int32_t openmpt_player_track_ended(openmpt_player_handle_t handle);
int32_t openmpt_player_played_frames(openmpt_player_handle_t handle);
void openmpt_metadata_clear(openmpt_metadata_t *metadata);
void openmpt_error_message_free(char *error_message);

#ifdef __cplusplus
}
#endif
