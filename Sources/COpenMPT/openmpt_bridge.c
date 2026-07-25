#include "openmpt_bridge.h"

#include <libopenmpt/libopenmpt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    openmpt_module *module;
    int32_t sample_rate;
    int32_t played_frames;
    int32_t track_ended;
} openmpt_player_t;

static char *copy_string(const char *value) {
    if (!value || !*value) return NULL;
    size_t length = strlen(value);
    char *copy = (char *)malloc(length + 1);
    if (!copy) return NULL;
    memcpy(copy, value, length + 1);
    return copy;
}

static void set_error(char **error_message, const char *message) {
    if (error_message) *error_message = copy_string(message ? message : "libopenmpt decoder failure.");
}

static openmpt_module *load_module(const char *path, char **error_message) {
    FILE *file = fopen(path, "rb");
    if (!file) {
        set_error(error_message, "Could not open tracker module.");
        return NULL;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        set_error(error_message, "Could not read tracker module size.");
        return NULL;
    }
    long file_size = ftell(file);
    if (file_size <= 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        set_error(error_message, "Tracker module is empty or unreadable.");
        return NULL;
    }
    void *data = malloc((size_t)file_size);
    if (!data || fread(data, 1, (size_t)file_size, file) != (size_t)file_size) {
        free(data);
        fclose(file);
        set_error(error_message, "Could not read tracker module.");
        return NULL;
    }
    fclose(file);

    int error = 0;
    const char *library_error = NULL;
    openmpt_module *module = openmpt_module_create_from_memory2(
        data, (size_t)file_size, NULL, NULL, NULL, NULL, &error, &library_error, NULL
    );
    free(data);
    if (!module) {
        set_error(error_message, library_error ? library_error : "libopenmpt could not load this module.");
        if (library_error) openmpt_free_string(library_error);
        return NULL;
    }
    if (library_error) openmpt_free_string(library_error);
    openmpt_module_ctl_set_text(module, "play.at_end", "stop");
    return module;
}

static void fill_metadata(openmpt_module *module, openmpt_metadata_t *metadata) {
    memset(metadata, 0, sizeof(*metadata));
    metadata->title = copy_string(openmpt_module_get_metadata(module, "title"));
    metadata->artist = copy_string(openmpt_module_get_metadata(module, "artist"));
    metadata->tracker = copy_string(openmpt_module_get_metadata(module, "tracker"));
    double duration = openmpt_module_get_duration_seconds(module);
    metadata->play_length_ms = duration > 0.0 && duration < 2147483.0 ? (int32_t)(duration * 1000.0) : 0;
}

openmpt_player_handle_t openmpt_player_create(const char *path, int32_t sample_rate, char **error_message) {
    if (!path || sample_rate <= 0) {
        set_error(error_message, "Tracker playback requires a file path and sample rate.");
        return NULL;
    }
    openmpt_module *module = load_module(path, error_message);
    if (!module) return NULL;
    openmpt_player_t *player = (openmpt_player_t *)calloc(1, sizeof(*player));
    if (!player) {
        openmpt_module_destroy(module);
        set_error(error_message, "Could not allocate tracker playback state.");
        return NULL;
    }
    player->module = module;
    player->sample_rate = sample_rate;
    return player;
}

void openmpt_player_destroy(openmpt_player_handle_t handle) {
    openmpt_player_t *player = (openmpt_player_t *)handle;
    if (!player) return;
    if (player->module) openmpt_module_destroy(player->module);
    free(player);
}

int32_t openmpt_inspect_file(const char *path, openmpt_metadata_t *metadata, char **error_message) {
    if (!path || !metadata) {
        set_error(error_message, "Tracker metadata inspection requires a file path.");
        return -1;
    }
    openmpt_module *module = load_module(path, error_message);
    if (!module) return -1;
    fill_metadata(module, metadata);
    openmpt_module_destroy(module);
    return 0;
}

int32_t openmpt_player_read_metadata(openmpt_player_handle_t handle, openmpt_metadata_t *metadata, char **error_message) {
    openmpt_player_t *player = (openmpt_player_t *)handle;
    if (!player || !player->module || !metadata) {
        set_error(error_message, "Tracker decoder is not initialized.");
        return -1;
    }
    fill_metadata(player->module, metadata);
    return 0;
}

int32_t openmpt_player_set_long_play(openmpt_player_handle_t handle, int32_t enabled, char **error_message) {
    openmpt_player_t *player = (openmpt_player_t *)handle;
    if (!player || !player->module) {
        set_error(error_message, "Tracker decoder is not initialized.");
        return -1;
    }
    if (!openmpt_module_set_repeat_count(player->module, enabled ? -1 : 0)) {
        set_error(error_message, "Could not configure tracker repeat playback.");
        return -1;
    }
    player->track_ended = 0;
    return 0;
}

int32_t openmpt_player_seek_milliseconds(openmpt_player_handle_t handle, int32_t milliseconds, char **error_message) {
    openmpt_player_t *player = (openmpt_player_t *)handle;
    if (!player || !player->module || milliseconds < 0) {
        set_error(error_message, "Invalid tracker seek request.");
        return -1;
    }
    openmpt_module_set_position_seconds(player->module, (double)milliseconds / 1000.0);
    player->played_frames = (int32_t)(((int64_t)milliseconds * player->sample_rate) / 1000);
    player->track_ended = 0;
    return 0;
}

int32_t openmpt_player_render_s16(openmpt_player_handle_t handle, int32_t requested_frames, int16_t *samples, int32_t *rendered_frames, char **error_message) {
    openmpt_player_t *player = (openmpt_player_t *)handle;
    if (!player || !player->module || requested_frames < 0 || (!samples && requested_frames > 0)) {
        set_error(error_message, "Invalid tracker render request.");
        return -1;
    }
    size_t rendered = openmpt_module_read_interleaved_stereo(player->module, player->sample_rate, (size_t)requested_frames, samples);
    player->played_frames += (int32_t)rendered;
    if (rendered == 0) player->track_ended = 1;
    if (rendered_frames) *rendered_frames = (int32_t)rendered;
    return 0;
}

int32_t openmpt_player_track_ended(openmpt_player_handle_t handle) {
    openmpt_player_t *player = (openmpt_player_t *)handle;
    return !player || player->track_ended;
}

int32_t openmpt_player_played_frames(openmpt_player_handle_t handle) {
    openmpt_player_t *player = (openmpt_player_t *)handle;
    return player ? player->played_frames : 0;
}

void openmpt_metadata_clear(openmpt_metadata_t *metadata) {
    if (!metadata) return;
    free(metadata->title);
    free(metadata->artist);
    free(metadata->tracker);
    memset(metadata, 0, sizeof(*metadata));
}

void openmpt_error_message_free(char *error_message) { free(error_message); }
