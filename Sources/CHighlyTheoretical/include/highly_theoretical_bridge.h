#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *highly_theoretical_player_handle_t;

highly_theoretical_player_handle_t highly_theoretical_player_create(const char *path, char **error_message);
void highly_theoretical_player_destroy(highly_theoretical_player_handle_t handle);
int32_t highly_theoretical_player_render_s16(
    highly_theoretical_player_handle_t handle,
    int32_t requested_frames,
    int16_t *samples,
    int32_t *rendered_frames,
    char **error_message
);
int32_t highly_theoretical_player_seek_milliseconds(
    highly_theoretical_player_handle_t handle,
    int32_t milliseconds,
    char **error_message
);
int32_t highly_theoretical_player_played_frames(highly_theoretical_player_handle_t handle);
void highly_theoretical_error_message_free(char *error_message);

#ifdef __cplusplus
}
#endif
