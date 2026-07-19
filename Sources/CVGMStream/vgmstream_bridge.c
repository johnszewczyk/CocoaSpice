#include "vgmstream_bridge.h"
#include "libvgmstream.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    libvgmstream_t *decoder;
    libstreamfile_t *streamfile;
    char *path;
    int subsong;
    int long_play;
} cocoa_vgmstream;

void cocoaspice_vgmstream_close(cocoaspice_vgmstream_handle_t handle);

static int open_decoder(cocoa_vgmstream *context, int long_play) {
    if (context->decoder) libvgmstream_free(context->decoder);
    if (context->streamfile) libstreamfile_close(context->streamfile);
    context->decoder = libvgmstream_init();
    context->streamfile = libstreamfile_open_from_stdio(context->path);
    if (!context->decoder || !context->streamfile) return -1;

    libvgmstream_config_t config = {0};
    config.allow_play_forever = long_play != 0;
    config.play_forever = long_play != 0;
    config.force_loop = long_play != 0;
    config.ignore_loop = false;
    config.force_sfmt = LIBVGMSTREAM_SFMT_PCM16;
    libvgmstream_setup(context->decoder, &config);
    if (libvgmstream_open_stream(context->decoder, context->streamfile, context->subsong) < 0) {
        return -1;
    }
    context->long_play = long_play != 0;
    return 0;
}

cocoaspice_vgmstream_handle_t cocoaspice_vgmstream_open(const char *path, int subsong, int sample_rate) {
    (void)sample_rate;
    if (!path || !path[0]) return NULL;
    cocoa_vgmstream *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    context->path = malloc(strlen(path) + 1);
    if (!context->path) {
        cocoaspice_vgmstream_close(context);
        return NULL;
    }
    memcpy(context->path, path, strlen(path) + 1);
    context->subsong = subsong;
    if (open_decoder(context, 0) < 0) {
        cocoaspice_vgmstream_close(context);
        return NULL;
    }
    return context;
}

void cocoaspice_vgmstream_close(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    if (!context) return;
    if (context->decoder) libvgmstream_free(context->decoder);
    if (context->streamfile) libstreamfile_close(context->streamfile);
    free(context->path);
    free(context);
}

int cocoaspice_vgmstream_set_long_play(cocoaspice_vgmstream_handle_t handle, int enabled) {
    cocoa_vgmstream *context = handle;
    if (!context) return -1;
    enabled = enabled != 0;
    if (context->long_play == enabled) return 0;
    return open_decoder(context, enabled);
}

int cocoaspice_vgmstream_read(cocoaspice_vgmstream_handle_t handle, int16_t *samples, int frames) {
    cocoa_vgmstream *context = handle;
    if (!context || !context->decoder) return -1;
    int status = libvgmstream_fill(context->decoder, samples, frames);
    if (status < 0 || !context->decoder->decoder) return -1;
    return context->decoder->decoder->buf_samples;
}

int cocoaspice_vgmstream_finished(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return !context || !context->decoder || !context->decoder->decoder || context->decoder->decoder->done;
}

int cocoaspice_vgmstream_channels(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return context && context->decoder && context->decoder->format ? context->decoder->format->channels : 0;
}

int cocoaspice_vgmstream_sample_rate(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return context && context->decoder && context->decoder->format ? context->decoder->format->sample_rate : 0;
}

int cocoaspice_vgmstream_subsong_count(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return context && context->decoder && context->decoder->format ? context->decoder->format->subsong_count : 0;
}

int64_t cocoaspice_vgmstream_played_frames(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return context && context->decoder ? libvgmstream_get_play_position(context->decoder) : 0;
}

int64_t cocoaspice_vgmstream_play_length_frames(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return context && context->decoder && context->decoder->format ? context->decoder->format->play_samples : 0;
}

int64_t cocoaspice_vgmstream_loop_length_frames(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    if (!context || !context->decoder || !context->decoder->format) return 0;
    return context->decoder->format->loop_end > context->decoder->format->loop_start
        ? context->decoder->format->loop_end - context->decoder->format->loop_start
        : 0;
}

int cocoaspice_vgmstream_has_loop(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return context && context->decoder && context->decoder->format && context->decoder->format->loop_flag;
}

void cocoaspice_vgmstream_seek(cocoaspice_vgmstream_handle_t handle, int64_t frame) {
    cocoa_vgmstream *context = handle;
    if (context && context->decoder) libvgmstream_seek(context->decoder, frame);
}

const char *cocoaspice_vgmstream_stream_name(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return context && context->decoder && context->decoder->format ? context->decoder->format->stream_name : "";
}

const char *cocoaspice_vgmstream_format_name(cocoaspice_vgmstream_handle_t handle) {
    cocoa_vgmstream *context = handle;
    return context && context->decoder && context->decoder->format ? context->decoder->format->meta_name : "";
}
