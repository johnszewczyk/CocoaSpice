#include "highly_theoretical_bridge.h"

#include "psflib.h"
#include "sega.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { sample_rate = 44100, cycles_per_sample = 256 };
enum { saturn_sound_ram_size = 0x80000 };

typedef struct {
    unsigned char *state;
    unsigned char *program;
    size_t program_size;
    uint32_t program_start;
    char *path;
    int32_t played_frames;
    char error[256];
} highly_theoretical_player_t;

static void *stdio_fopen(const char *path) { return fopen(path, "rb"); }
static size_t stdio_fread(void *p, size_t size, size_t count, void *file) { return fread(p, size, count, (FILE *)file); }
static int stdio_fseek(void *file, int64_t offset, int whence) { return fseek((FILE *)file, (long)offset, whence); }
static int stdio_fclose(void *file) { return fclose((FILE *)file); }
static long stdio_ftell(void *file) { return ftell((FILE *)file); }

static const psf_file_callbacks file_callbacks = {
    "\\/:", stdio_fopen, stdio_fread, stdio_fseek, stdio_fclose, stdio_ftell
};

static char *copy_string(const char *value) {
    if (!value || !*value) return NULL;
    const size_t length = strlen(value) + 1;
    char *copy = (char *)malloc(length);
    if (copy) memcpy(copy, value, length);
    return copy;
}

static void set_error(char **destination, const char *value) {
    if (destination) *destination = copy_string(value ? value : "SSF decoder failure.");
}

static uint32_t read_le32(const uint8_t *value) {
    return (uint32_t)value[0]
        | ((uint32_t)value[1] << 8)
        | ((uint32_t)value[2] << 16)
        | ((uint32_t)value[3] << 24);
}

static int load_callback(void *context, const uint8_t *exe, size_t exe_size, const uint8_t *reserved, size_t reserved_size) {
    highly_theoretical_player_t *player = (highly_theoretical_player_t *)context;
    (void)reserved;
    (void)reserved_size;
    if (!exe || exe_size < 4) {
        snprintf(player->error, sizeof(player->error), "SSF program section is malformed.");
        return -1;
    }

    const uint32_t source_start = read_le32(exe) & 0x7FFFFF;
    const size_t source_size = exe_size - 4;
    if (source_size > UINT32_MAX || source_start > UINT32_MAX - (uint32_t)source_size) {
        snprintf(player->error, sizeof(player->error), "SSF program section is too large.");
        return -1;
    }

    if (!player->program) {
        player->program = (unsigned char *)malloc(exe_size);
        if (!player->program) {
            snprintf(player->error, sizeof(player->error), "Could not allocate SSF program image.");
            return -1;
        }
        memcpy(player->program, exe, exe_size);
        player->program_start = source_start;
        player->program_size = exe_size;
        return 0;
    }

    uint32_t destination_start = player->program_start;
    size_t destination_size = player->program_size - 4;
    if (source_start < destination_start) {
        const size_t offset = destination_start - source_start;
        if (destination_size > SIZE_MAX - offset) goto overflow;
        unsigned char *resized = (unsigned char *)realloc(player->program, 4 + destination_size + offset);
        if (!resized) goto allocation_failure;
        player->program = resized;
        memmove(player->program + 4 + offset, player->program + 4, destination_size);
        memset(player->program + 4, 0, offset);
        destination_size += offset;
        destination_start = source_start;
        player->program_start = destination_start;
        player->program[0] = (unsigned char)(destination_start & 0xFF);
        player->program[1] = (unsigned char)((destination_start >> 8) & 0xFF);
        player->program[2] = (unsigned char)((destination_start >> 16) & 0xFF);
        player->program[3] = (unsigned char)((destination_start >> 24) & 0xFF);
    }

    const size_t source_offset = source_start - destination_start;
    if (source_offset > SIZE_MAX - source_size) goto overflow;
    const size_t required_size = source_offset + source_size;
    if (required_size > destination_size) {
        unsigned char *resized = (unsigned char *)realloc(player->program, 4 + required_size);
        if (!resized) goto allocation_failure;
        player->program = resized;
        memset(player->program + 4 + destination_size, 0, required_size - destination_size);
        destination_size = required_size;
    }
    memcpy(player->program + 4 + source_offset, exe + 4, source_size);
    player->program_size = 4 + destination_size;
    return 0;

overflow:
    snprintf(player->error, sizeof(player->error), "SSF program image is too large.");
    return -1;
allocation_failure:
    snprintf(player->error, sizeof(player->error), "Could not extend SSF program image.");
    return -1;
}

static int recreate(highly_theoretical_player_t *player, const char *path, char **error_message) {
    if (sega_init() != 0) {
        set_error(error_message, "Sega Saturn emulator initialization failed.");
        return -1;
    }
    if (!player->state) {
        player->state = (unsigned char *)malloc(sega_get_state_size(1));
        if (!player->state) {
            set_error(error_message, "Could not allocate Sega Saturn emulator state.");
            return -1;
        }
    }
    sega_clear_state(player->state, 1);
    player->played_frames = 0;
    player->error[0] = '\0';
    free(player->program);
    player->program = NULL;
    player->program_size = 0;
    player->program_start = 0;
    if (psf_load(path, &file_callbacks, 0x11, load_callback, player, NULL, NULL, 0) != 0x11) {
        set_error(error_message, player->error[0] ? player->error : "Could not load SSF or its SSFLIB dependencies.");
        return -1;
    }
    if (!player->program || player->program_size < 5) {
        set_error(error_message, "SSF did not contain a playable program image.");
        return -1;
    }
    size_t upload_size = player->program_size;
    if (player->program_start >= saturn_sound_ram_size) {
        set_error(error_message, "SSF program starts outside Saturn sound RAM.");
        return -1;
    }
    const size_t maximum_upload_size = 4 + (saturn_sound_ram_size - player->program_start);
    if (upload_size > maximum_upload_size) upload_size = maximum_upload_size;
    if (sega_upload_program(player->state, player->program, (uint32)upload_size) != 0) {
        set_error(error_message, "SSF program image could not be loaded.");
        return -1;
    }
    return 0;
}

highly_theoretical_player_handle_t highly_theoretical_player_create(const char *path, char **error_message) {
    if (!path || !*path) {
        set_error(error_message, "SSF decoder requires a file path.");
        return NULL;
    }
    highly_theoretical_player_t *player = (highly_theoretical_player_t *)calloc(1, sizeof(*player));
    if (!player) {
        set_error(error_message, "Could not allocate SSF decoder.");
        return NULL;
    }
    if (recreate(player, path, error_message) != 0) {
        highly_theoretical_player_destroy(player);
        return NULL;
    }
    player->path = copy_string(path);
    if (!player->path) {
        highly_theoretical_player_destroy(player);
        set_error(error_message, "Could not retain SSF playback path.");
        return NULL;
    }
    return player;
}

void highly_theoretical_player_destroy(highly_theoretical_player_handle_t handle) {
    highly_theoretical_player_t *player = (highly_theoretical_player_t *)handle;
    if (!player) return;
    free(player->state);
    free(player->program);
    free(player->path);
    free(player);
}

int32_t highly_theoretical_player_render_s16(
    highly_theoretical_player_handle_t handle,
    int32_t requested_frames,
    int16_t *samples,
    int32_t *rendered_frames,
    char **error_message
) {
    highly_theoretical_player_t *player = (highly_theoretical_player_t *)handle;
    if (!player || requested_frames < 0 || (requested_frames > 0 && !samples)) {
        set_error(error_message, "SSF decoder is not initialized.");
        return -1;
    }
    uint32_t rendered = (uint32_t)requested_frames;
    const int32_t cycles = requested_frames > INT32_MAX / cycles_per_sample
        ? INT32_MAX
        : requested_frames * cycles_per_sample;
    if (sega_execute(player->state, cycles, samples, &rendered) < 0) {
        set_error(error_message, "Sega Saturn emulator execution failed.");
        return -1;
    }
    player->played_frames += (int32_t)rendered;
    if (rendered_frames) *rendered_frames = (int32_t)rendered;
    return 0;
}

int32_t highly_theoretical_player_seek_milliseconds(
    highly_theoretical_player_handle_t handle,
    int32_t milliseconds,
    char **error_message
) {
    highly_theoretical_player_t *player = (highly_theoretical_player_t *)handle;
    if (!player || milliseconds < 0 || !player->path) {
        set_error(error_message, "Invalid SSF seek request.");
        return -1;
    }
    if (recreate(player, player->path, error_message) != 0) return -1;
    int32_t remaining = (int32_t)(((int64_t)milliseconds * sample_rate) / 1000);
    int16_t scratch[2048 * 2];
    while (remaining > 0) {
        const int32_t frames = remaining > 2048 ? 2048 : remaining;
        int32_t rendered = 0;
        if (highly_theoretical_player_render_s16(player, frames, scratch, &rendered, error_message) != 0) return -1;
        if (rendered <= 0) {
            set_error(error_message, "SSF decoder stalled while seeking.");
            return -1;
        }
        remaining -= rendered;
    }
    return 0;
}

int32_t highly_theoretical_player_played_frames(highly_theoretical_player_handle_t handle) {
    const highly_theoretical_player_t *player = (const highly_theoretical_player_t *)handle;
    return player ? player->played_frames : 0;
}

void highly_theoretical_error_message_free(char *error_message) { free(error_message); }
