#include "ffmpeg_audio_bridge.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libswresample/swresample.h>

#include <stdlib.h>

typedef struct {
    AVFormatContext *format;
    AVCodecContext *codec;
    AVPacket *packet;
    AVFrame *frame;
    SwrContext *resampler;
    int stream_index;
    int sample_rate;
    int sent_eof;
    int finished;
    int64_t played_frames;
    int64_t length_frames;
} cocoa_ffmpeg_audio;

void cocoaspice_ffmpeg_audio_close(cocoaspice_ffmpeg_audio_handle_t handle) {
    cocoa_ffmpeg_audio *context = handle;
    if (!context) return;
    swr_free(&context->resampler);
    av_frame_free(&context->frame);
    av_packet_free(&context->packet);
    avcodec_free_context(&context->codec);
    avformat_close_input(&context->format);
    free(context);
}

cocoaspice_ffmpeg_audio_handle_t cocoaspice_ffmpeg_audio_open(const char *path, int output_sample_rate) {
    if (!path || !path[0]) return NULL;
    cocoa_ffmpeg_audio *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    if (avformat_open_input(&context->format, path, NULL, NULL) < 0 ||
        avformat_find_stream_info(context->format, NULL) < 0) {
        cocoaspice_ffmpeg_audio_close(context);
        return NULL;
    }
    context->stream_index = av_find_best_stream(context->format, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (context->stream_index < 0) {
        cocoaspice_ffmpeg_audio_close(context);
        return NULL;
    }
    AVStream *stream = context->format->streams[context->stream_index];
    const AVCodec *decoder = avcodec_find_decoder(stream->codecpar->codec_id);
    context->codec = decoder ? avcodec_alloc_context3(decoder) : NULL;
    if (!context->codec || avcodec_parameters_to_context(context->codec, stream->codecpar) < 0 ||
        avcodec_open2(context->codec, decoder, NULL) < 0) {
        cocoaspice_ffmpeg_audio_close(context);
        return NULL;
    }
    context->sample_rate = output_sample_rate > 0 ? output_sample_rate : context->codec->sample_rate;
    AVChannelLayout output_layout;
    av_channel_layout_default(&output_layout, 2);
    if (swr_alloc_set_opts2(&context->resampler, &output_layout, AV_SAMPLE_FMT_S16, context->sample_rate,
                            &context->codec->ch_layout, context->codec->sample_fmt,
                            context->codec->sample_rate, 0, NULL) < 0 ||
        !context->resampler || swr_init(context->resampler) < 0) {
        av_channel_layout_uninit(&output_layout);
        cocoaspice_ffmpeg_audio_close(context);
        return NULL;
    }
    av_channel_layout_uninit(&output_layout);
    context->packet = av_packet_alloc();
    context->frame = av_frame_alloc();
    if (!context->packet || !context->frame) {
        cocoaspice_ffmpeg_audio_close(context);
        return NULL;
    }
    int64_t duration = stream->duration != AV_NOPTS_VALUE
        ? av_rescale_q(stream->duration, stream->time_base, (AVRational){1, context->sample_rate})
        : context->format->duration != AV_NOPTS_VALUE
            ? av_rescale_q(context->format->duration, AV_TIME_BASE_Q, (AVRational){1, context->sample_rate})
            : 0;
    context->length_frames = duration > 0 ? duration : 0;
    return context;
}

int cocoaspice_ffmpeg_audio_read(cocoaspice_ffmpeg_audio_handle_t handle, int16_t *samples, int frames) {
    cocoa_ffmpeg_audio *context = handle;
    if (!context || !samples || frames <= 0 || context->finished) return 0;
    int written = 0;
    while (written < frames) {
        int receive = avcodec_receive_frame(context->codec, context->frame);
        if (receive == 0) {
            uint8_t *output[] = {(uint8_t *)(samples + written * 2)};
            int converted = swr_convert(context->resampler, output, frames - written,
                                        (const uint8_t **)context->frame->extended_data, context->frame->nb_samples);
            av_frame_unref(context->frame);
            if (converted < 0) return written > 0 ? written : -1;
            written += converted;
            continue;
        }
        if (receive != AVERROR(EAGAIN) && receive != AVERROR_EOF) return written > 0 ? written : -1;
        if (context->sent_eof) {
            uint8_t *output[] = {(uint8_t *)(samples + written * 2)};
            int flushed = swr_convert(context->resampler, output, frames - written, NULL, 0);
            if (flushed > 0) {
                written += flushed;
                continue;
            }
            context->finished = 1;
            break;
        }
        int packet_status;
        do {
            packet_status = av_read_frame(context->format, context->packet);
            if (packet_status >= 0 && context->packet->stream_index != context->stream_index) av_packet_unref(context->packet);
        } while (packet_status >= 0 && context->packet->stream_index != context->stream_index);
        if (packet_status < 0) {
            context->sent_eof = 1;
            if (avcodec_send_packet(context->codec, NULL) < 0) return written > 0 ? written : -1;
        } else {
            int sent = avcodec_send_packet(context->codec, context->packet);
            av_packet_unref(context->packet);
            if (sent < 0 && sent != AVERROR(EAGAIN)) return written > 0 ? written : -1;
        }
    }
    context->played_frames += written;
    return written;
}

int cocoaspice_ffmpeg_audio_finished(cocoaspice_ffmpeg_audio_handle_t handle) {
    cocoa_ffmpeg_audio *context = handle;
    return !context || context->finished;
}
int cocoaspice_ffmpeg_audio_sample_rate(cocoaspice_ffmpeg_audio_handle_t handle) {
    cocoa_ffmpeg_audio *context = handle;
    return context ? context->sample_rate : 0;
}
int64_t cocoaspice_ffmpeg_audio_played_frames(cocoaspice_ffmpeg_audio_handle_t handle) {
    cocoa_ffmpeg_audio *context = handle;
    return context ? context->played_frames : 0;
}
int64_t cocoaspice_ffmpeg_audio_length_frames(cocoaspice_ffmpeg_audio_handle_t handle) {
    cocoa_ffmpeg_audio *context = handle;
    return context ? context->length_frames : 0;
}
void cocoaspice_ffmpeg_audio_seek(cocoaspice_ffmpeg_audio_handle_t handle, int64_t frame) {
    cocoa_ffmpeg_audio *context = handle;
    if (!context) return;
    AVStream *stream = context->format->streams[context->stream_index];
    int64_t timestamp = av_rescale_q(frame, (AVRational){1, context->sample_rate}, stream->time_base);
    if (av_seek_frame(context->format, context->stream_index, timestamp, AVSEEK_FLAG_BACKWARD) >= 0) {
        avcodec_flush_buffers(context->codec);
        swr_close(context->resampler);
        swr_init(context->resampler);
        context->played_frames = frame;
        context->sent_eof = 0;
        context->finished = 0;
    }
}
const char *cocoaspice_ffmpeg_audio_title(cocoaspice_ffmpeg_audio_handle_t handle) {
    cocoa_ffmpeg_audio *context = handle;
    AVDictionaryEntry *entry = context ? av_dict_get(context->format->metadata, "title", NULL, 0) : NULL;
    return entry ? entry->value : "";
}
const char *cocoaspice_ffmpeg_audio_format_name(cocoaspice_ffmpeg_audio_handle_t handle) {
    cocoa_ffmpeg_audio *context = handle;
    return context && context->format && context->format->iformat ? context->format->iformat->long_name : "FFmpeg audio";
}
