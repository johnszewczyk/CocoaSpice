#include "highlycomplete_bridge.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include <mgba/flags.h>
#include <mgba/core/config.h>
#include <mgba/core/core.h>
#include <mgba/core/log.h>
#include <mgba-util/audio-buffer.h>
#include <mgba-util/vfs.h>

#include "third_party/psflib/psflib.h"

namespace {

constexpr int kChannelCount = 2;
constexpr size_t kAudioChunkFrames = 2048;
constexpr int kMaxEmptyRunFrames = 240;
constexpr unsigned kDefaultGSFSampleRate = 32768;

struct GSFLoaderState {
    int entrySet = 0;
    uint32_t entry = 0;
    uint8_t* data = nullptr;
    size_t dataSize = 0;
    size_t capacity = 0;
};

struct MetadataCollector {
    std::string title;
    std::string game;
    std::string artist;
    std::string comment;
    int lengthMs = 0;
    int fadeMs = 0;
};

struct HighlyCompleteHandle {
    std::vector<uint8_t> romData;
    highlycomplete_metadata_t metadata{};
    mCore* core = nullptr;
    VFile* romView = nullptr;
    mAVStream stream{};
    std::vector<int16_t> resampleBuffer;
    int32_t requestedSampleRate = 44100;
    int32_t activeSampleRate = static_cast<int32_t>(kDefaultGSFSampleRate);
    int64_t playedFrames = 0;
    double resampleSourcePosition = 0;
    bool playbackEnded = false;
    bool coreInitialized = false;
    bool configInitialized = false;
    bool romViewOwnedByCore = false;
};

HighlyCompleteHandle* handleFromStream(mAVStream* stream) {
    if (stream == nullptr) {
        return nullptr;
    }
    auto* bytes = reinterpret_cast<char*>(stream);
    return reinterpret_cast<HighlyCompleteHandle*>(bytes - offsetof(HighlyCompleteHandle, stream));
}

void highlyCompleteAudioRateChanged(mAVStream* stream, unsigned rate) {
    auto* handle = handleFromStream(stream);
    if (handle == nullptr) {
        return;
    }
    handle->activeSampleRate = rate > 0 ? static_cast<int32_t>(rate) : static_cast<int32_t>(kDefaultGSFSampleRate);
}

char* duplicateCString(const std::string& value) {
    char* buffer = static_cast<char*>(std::malloc(value.size() + 1));
    if (buffer == nullptr) {
        return nullptr;
    }
    std::memcpy(buffer, value.c_str(), value.size() + 1);
    return buffer;
}

void setError(char** errorMessage, const std::string& message) {
    if (errorMessage == nullptr) {
        return;
    }
    *errorMessage = duplicateCString(message);
}

void clearMetadata(highlycomplete_metadata_t* metadata) {
    if (metadata == nullptr) {
        return;
    }

    std::free(metadata->title);
    std::free(metadata->game);
    std::free(metadata->system);
    std::free(metadata->artist);
    std::free(metadata->comment);
    std::memset(metadata, 0, sizeof(*metadata));
}

std::string lowercased(const char* text) {
    std::string value = text == nullptr ? "" : text;
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

int parseTimeMilliseconds(const char* rawValue) {
    if (rawValue == nullptr) {
        return 0;
    }

    std::string value(rawValue);
    size_t lineBreak = value.find_first_of("\r\n");
    if (lineBreak != std::string::npos) {
        value.resize(lineBreak);
    }
    if (value.empty()) {
        return 0;
    }

    std::vector<std::string> components;
    size_t start = 0;
    while (true) {
        size_t separator = value.find(':', start);
        if (separator == std::string::npos) {
            components.push_back(value.substr(start));
            break;
        }
        components.push_back(value.substr(start, separator - start));
        start = separator + 1;
    }

    double multiplier = 1000.0;
    double totalMilliseconds = 0.0;
    bool first = true;
    for (auto iterator = components.rbegin(); iterator != components.rend(); ++iterator) {
        try {
            double parsed = std::stod(*iterator);
            totalMilliseconds += parsed * multiplier;
        } catch (...) {
            return 0;
        }
        multiplier *= first ? 60.0 : 60.0;
        first = false;
    }

    return static_cast<int>(std::lround(totalMilliseconds));
}

int gsfInfoCallback(void* context, const char* name, const char* value) {
    auto* metadata = static_cast<MetadataCollector*>(context);
    if (metadata == nullptr || name == nullptr || value == nullptr) {
        return 0;
    }

    std::string key = lowercased(name);
    if (key == "title") {
        if (metadata->title.empty()) {
            metadata->title = value;
        }
    } else if (key == "game" || key == "album") {
        if (metadata->game.empty()) {
            metadata->game = value;
        }
    } else if (key == "artist" || key == "composer") {
        if (metadata->artist.empty()) {
            metadata->artist = value;
        }
    } else if (key == "comment" || key == "copyright") {
        if (!metadata->comment.empty()) {
            metadata->comment += " | ";
        }
        metadata->comment += value;
    } else if (key == "length") {
        metadata->lengthMs = parseTimeMilliseconds(value);
    } else if (key == "fade") {
        metadata->fadeMs = parseTimeMilliseconds(value);
    }

    return 0;
}

int gsfLoader(
    void* context,
    const uint8_t* exe,
    size_t exeSize,
    const uint8_t* reserved,
    size_t reservedSize
) {
    (void)reserved;
    (void)reservedSize;

    if (exe == nullptr || exeSize < 12) {
        return -1;
    }

    auto* state = static_cast<GSFLoaderState*>(context);
    if (state == nullptr) {
        return -1;
    }

    auto getLE32 = [](const uint8_t* bytes) -> uint32_t {
        return static_cast<uint32_t>(bytes[0]) |
            (static_cast<uint32_t>(bytes[1]) << 8U) |
            (static_cast<uint32_t>(bytes[2]) << 16U) |
            (static_cast<uint32_t>(bytes[3]) << 24U);
    };

    const uint32_t entry = getLE32(exe + 0);
    const uint32_t offset = getLE32(exe + 4) & 0x1FFFFFFU;
    const uint32_t size = getLE32(exe + 8);
    if (size < exeSize - 12) {
        return -1;
    }

    if (!state->entrySet) {
        state->entry = entry;
        state->entrySet = 1;
    }

    uint8_t* data = state->data;
    size_t capacity = state->capacity;
    size_t imageSize = state->dataSize;
    state->data = nullptr;
    state->dataSize = 0;
    state->capacity = 0;

    const size_t requiredSize = static_cast<size_t>(offset) + static_cast<size_t>(size);
    if (requiredSize == 0) {
        state->data = data;
        state->dataSize = imageSize;
        state->capacity = capacity;
        return 0;
    }

    if (data == nullptr || capacity < requiredSize) {
        size_t roundedSize = requiredSize;
        roundedSize -= 1;
        roundedSize |= roundedSize >> 1;
        roundedSize |= roundedSize >> 2;
        roundedSize |= roundedSize >> 4;
        roundedSize |= roundedSize >> 8;
        roundedSize |= roundedSize >> 16;
        roundedSize += 1;

        if (data == nullptr) {
            data = static_cast<uint8_t*>(std::malloc(roundedSize + 10));
            if (data == nullptr) {
                return -1;
            }
            std::memset(data, 0, roundedSize + 10);
        } else {
            uint8_t* resized = static_cast<uint8_t*>(std::realloc(data, roundedSize + 10));
            if (resized == nullptr) {
                std::free(data);
                return -1;
            }
            std::memset(resized + capacity, 0, (roundedSize + 10) - capacity);
            data = resized;
        }
        capacity = roundedSize;
    }

    std::memcpy(data + offset, exe + 12, size);
    state->data = data;
    state->dataSize = std::max(imageSize, requiredSize);
    state->capacity = capacity;
    return 0;
}

void gsfLogger(struct mLogger* logger, int category, enum mLogLevel level, const char* format, va_list args) {
    (void)logger;
    (void)category;
    (void)level;
    (void)format;
    (void)args;
}

struct mLogger kSilentLogger = {
    .log = gsfLogger,
    .filter = nullptr
};

void* psfOpen(const char* path) {
    return std::fopen(path, "rb");
}

size_t psfRead(void* buffer, size_t size, size_t count, void* handle) {
    return std::fread(buffer, size, count, static_cast<std::FILE*>(handle));
}

int psfSeek(void* handle, int64_t offset, int whence) {
    return std::fseek(static_cast<std::FILE*>(handle), static_cast<long>(offset), whence);
}

int psfClose(void* handle) {
    return std::fclose(static_cast<std::FILE*>(handle));
}

long psfTell(void* handle) {
    return std::ftell(static_cast<std::FILE*>(handle));
}

const psf_file_callbacks kPSFCallbacks = {
    .path_separators = "/\\",
    .fopen = psfOpen,
    .fread = psfRead,
    .fseek = psfSeek,
    .fclose = psfClose,
    .ftell = psfTell
};

void closeCore(HighlyCompleteHandle* handle) {
    if (handle == nullptr) {
        return;
    }

    if (handle->core != nullptr) {
        if (handle->configInitialized) {
            mCoreConfigDeinit(&handle->core->config);
            handle->configInitialized = false;
        }
        if (handle->coreInitialized) {
            handle->core->deinit(handle->core);
            handle->coreInitialized = false;
        }
        handle->core = nullptr;
    }
    if (handle->romView != nullptr && !handle->romViewOwnedByCore) {
        handle->romView->close(handle->romView);
    }
    handle->romView = nullptr;
    handle->romViewOwnedByCore = false;
    handle->resampleBuffer.clear();
    handle->resampleSourcePosition = 0;
}

bool initializeCore(HighlyCompleteHandle* handle, char** errorMessage) {
    if (handle == nullptr || handle->romData.empty()) {
        setError(errorMessage, "HighlyComplete has no decoded GSF payload.");
        return false;
    }

    closeCore(handle);
    mLogSetDefaultLogger(&kSilentLogger);
    handle->stream.audioRateChanged = highlyCompleteAudioRateChanged;

    handle->romView = VFileFromConstMemory(handle->romData.data(), handle->romData.size());
    if (handle->romView == nullptr) {
        setError(errorMessage, "HighlyComplete could not create an mGBA ROM view.");
        return false;
    }

    handle->core = mCoreFindVF(handle->romView);
    if (handle->core == nullptr) {
        closeCore(handle);
        setError(errorMessage, "HighlyComplete could not recognize this GSF payload.");
        return false;
    }

    if (!handle->core->init(handle->core)) {
        closeCore(handle);
        setError(errorMessage, "HighlyComplete could not initialize the mGBA core.");
        return false;
    }
    handle->coreInitialized = true;

    handle->core->setAVStream(handle->core, &handle->stream);
    mCoreInitConfig(handle->core, nullptr);
    handle->configInitialized = true;
    handle->core->setAudioBufferSize(handle->core, kAudioChunkFrames);

    mCoreOptions options = {};
    options.skipBios = true;
    options.useBios = false;
    options.sampleRate = kDefaultGSFSampleRate;
    options.volume = 0x100;
    mCoreConfigLoadDefaults(&handle->core->config, &options);

    if (!handle->core->loadROM(handle->core, handle->romView)) {
        closeCore(handle);
        setError(errorMessage, "HighlyComplete could not load the GSF ROM image.");
        return false;
    }
    handle->romViewOwnedByCore = true;

    handle->core->reset(handle->core);
    if (handle->activeSampleRate <= 0) {
        handle->activeSampleRate = static_cast<int32_t>(kDefaultGSFSampleRate);
    }
    handle->playedFrames = 0;
    handle->resampleBuffer.clear();
    handle->resampleSourcePosition = 0;
    handle->playbackEnded = false;
    return true;
}

void populateMetadata(
    highlycomplete_metadata_t* metadata,
    const MetadataCollector& collector
) {
    clearMetadata(metadata);
    metadata->title = duplicateCString(collector.title);
    metadata->game = duplicateCString(collector.game);
    metadata->system = duplicateCString("Game Boy Advance");
    metadata->artist = duplicateCString(collector.artist);
    metadata->comment = duplicateCString(collector.comment);
    metadata->intro_length_ms = collector.lengthMs;
    metadata->loop_length_ms = 0;
    metadata->play_length_ms = collector.lengthMs;
    metadata->fade_length_ms = collector.fadeMs;
    metadata->track_count = 1;
}

int32_t copyMetadata(
    const highlycomplete_metadata_t& source,
    highlycomplete_metadata_t* destination,
    char** errorMessage
) {
    if (destination == nullptr) {
        setError(errorMessage, "HighlyComplete metadata target was not initialized.");
        return 1;
    }

    clearMetadata(destination);
    destination->title = duplicateCString(source.title == nullptr ? "" : source.title);
    destination->game = duplicateCString(source.game == nullptr ? "" : source.game);
    destination->system = duplicateCString(source.system == nullptr ? "" : source.system);
    destination->artist = duplicateCString(source.artist == nullptr ? "" : source.artist);
    destination->comment = duplicateCString(source.comment == nullptr ? "" : source.comment);
    destination->intro_length_ms = source.intro_length_ms;
    destination->loop_length_ms = source.loop_length_ms;
    destination->play_length_ms = source.play_length_ms;
    destination->fade_length_ms = source.fade_length_ms;
    destination->track_count = source.track_count;
    return 0;
}

int32_t renderFrames(
    HighlyCompleteHandle* handle,
    int32_t requestedFrames,
    int16_t* output,
    int32_t* renderedFrames,
    char** errorMessage
) {
    if (handle == nullptr || handle->core == nullptr || renderedFrames == nullptr) {
        setError(errorMessage, "HighlyComplete render arguments were incomplete.");
        return 1;
    }

    *renderedFrames = 0;
    if (requestedFrames <= 0 || handle->playbackEnded) {
        return 0;
    }

    auto* buffer = handle->core->getAudioBuffer(handle->core);
    if (buffer == nullptr) {
        setError(errorMessage, "HighlyComplete could not access the audio buffer.");
        return 1;
    }

    auto availableBufferedFrames = [&]() -> size_t {
        return handle->resampleBuffer.size() / kChannelCount;
    };

    auto compactResampleBuffer = [&]() {
        size_t dropFrames = static_cast<size_t>(handle->resampleSourcePosition);
        if (dropFrames == 0) {
            return;
        }
        size_t bufferedFrames = availableBufferedFrames();
        if (dropFrames >= bufferedFrames) {
            handle->resampleBuffer.clear();
            handle->resampleSourcePosition = 0;
            return;
        }
        handle->resampleBuffer.erase(
            handle->resampleBuffer.begin(),
            handle->resampleBuffer.begin() + static_cast<std::ptrdiff_t>(dropFrames * kChannelCount)
        );
        handle->resampleSourcePosition -= static_cast<double>(dropFrames);
    };

    auto appendSourceAudio = [&](size_t minimumFramesNeeded) -> bool {
        int emptyRunFrames = 0;
        while (availableBufferedFrames() < minimumFramesNeeded && !handle->playbackEnded) {
            size_t toRead = minimumFramesNeeded - availableBufferedFrames();
            if (toRead > kAudioChunkFrames) {
                toRead = kAudioChunkFrames;
            }

            std::vector<int16_t> chunk(toRead * kChannelCount);
            size_t available = mAudioBufferRead(buffer, chunk.data(), toRead);
            if (available > 0) {
                handle->resampleBuffer.insert(
                    handle->resampleBuffer.end(),
                    chunk.begin(),
                    chunk.begin() + static_cast<std::ptrdiff_t>(available * kChannelCount)
                );
                emptyRunFrames = 0;
                continue;
            }

            handle->core->runFrame(handle->core);
            if (mAudioBufferAvailable(buffer) == 0) {
                emptyRunFrames += 1;
                if (emptyRunFrames >= kMaxEmptyRunFrames) {
                    handle->playbackEnded = true;
                    break;
                }
            } else {
                emptyRunFrames = 0;
            }
        }

        return availableBufferedFrames() >= minimumFramesNeeded;
    };

    int32_t totalRendered = 0;
    while (totalRendered < requestedFrames) {
        const double sourceRate = static_cast<double>(std::max(handle->activeSampleRate, 1));
        const double outputRate = static_cast<double>(std::max(handle->requestedSampleRate, 1));
        const double sourceStep = sourceRate / outputRate;

        size_t baseFrame = static_cast<size_t>(handle->resampleSourcePosition);
        size_t minimumFramesNeeded = baseFrame + 2;
        if (!appendSourceAudio(minimumFramesNeeded)) {
            size_t bufferedFrames = availableBufferedFrames();
            if (bufferedFrames == 0) {
                break;
            }
            minimumFramesNeeded = std::min(minimumFramesNeeded, bufferedFrames);
        }

        size_t bufferedFrames = availableBufferedFrames();
        if (bufferedFrames == 0) {
            break;
        }

        baseFrame = static_cast<size_t>(handle->resampleSourcePosition);
        if (baseFrame >= bufferedFrames) {
            compactResampleBuffer();
            continue;
        }

        size_t nextFrame = std::min(baseFrame + 1, bufferedFrames - 1);
        double fraction = handle->resampleSourcePosition - static_cast<double>(baseFrame);

        int16_t left0 = handle->resampleBuffer[(baseFrame * kChannelCount) + 0];
        int16_t right0 = handle->resampleBuffer[(baseFrame * kChannelCount) + 1];
        int16_t left1 = handle->resampleBuffer[(nextFrame * kChannelCount) + 0];
        int16_t right1 = handle->resampleBuffer[(nextFrame * kChannelCount) + 1];

        double interpolatedLeft = static_cast<double>(left0) + (static_cast<double>(left1) - static_cast<double>(left0)) * fraction;
        double interpolatedRight = static_cast<double>(right0) + (static_cast<double>(right1) - static_cast<double>(right0)) * fraction;

        if (output != nullptr) {
            size_t outputIndex = static_cast<size_t>(totalRendered) * kChannelCount;
            long clampedLeft = std::lround(interpolatedLeft);
            long clampedRight = std::lround(interpolatedRight);
            if (clampedLeft < INT16_MIN) {
                clampedLeft = INT16_MIN;
            } else if (clampedLeft > INT16_MAX) {
                clampedLeft = INT16_MAX;
            }
            if (clampedRight < INT16_MIN) {
                clampedRight = INT16_MIN;
            } else if (clampedRight > INT16_MAX) {
                clampedRight = INT16_MAX;
            }
            output[outputIndex + 0] = static_cast<int16_t>(clampedLeft);
            output[outputIndex + 1] = static_cast<int16_t>(clampedRight);
        }

        handle->resampleSourcePosition += sourceStep;
        handle->playedFrames += 1;
        totalRendered += 1;

        if (handle->resampleSourcePosition >= 1024.0) {
            compactResampleBuffer();
        }
    }

    compactResampleBuffer();
    if (totalRendered == 0 && handle->playbackEnded) {
        handle->resampleBuffer.clear();
        handle->resampleSourcePosition = 0;
    }

    *renderedFrames = totalRendered;
    return 0;
}

void destroyHandle(HighlyCompleteHandle* handle) {
    if (handle == nullptr) {
        return;
    }

    closeCore(handle);
    clearMetadata(&handle->metadata);
    delete handle;
}

int32_t loadGSFFile(HighlyCompleteHandle* handle, const char* path, char** errorMessage) {
    if (handle == nullptr || path == nullptr) {
        setError(errorMessage, "HighlyComplete needs a file path.");
        return 1;
    }

    GSFLoaderState loaderState;
    MetadataCollector collector;
    int version = psf_load(
        path,
        &kPSFCallbacks,
        0x22,
        gsfLoader,
        &loaderState,
        gsfInfoCallback,
        &collector,
        1
    );
    if (version != 0x22) {
        if (loaderState.data != nullptr) {
            std::free(loaderState.data);
        }
        setError(errorMessage, "HighlyComplete could not decode this GSF/miniGSF file.");
        return 1;
    }

    handle->romData.assign(loaderState.data, loaderState.data + loaderState.dataSize);
    std::free(loaderState.data);

    populateMetadata(&handle->metadata, collector);

    if (!initializeCore(handle, errorMessage)) {
        return 1;
    }

    return 0;
}

int32_t inspectGSFFile(
    const char* path,
    highlycomplete_metadata_t* metadata,
    int32_t* trackCount,
    char** errorMessage
) {
    MetadataCollector collector;
    int version = psf_load(
        path,
        &kPSFCallbacks,
        0x22,
        nullptr,
        nullptr,
        gsfInfoCallback,
        &collector,
        1
    );
    if (version != 0x22) {
        setError(errorMessage, "HighlyComplete could not decode this GSF/miniGSF file.");
        return 1;
    }

    if (metadata != nullptr) {
        populateMetadata(metadata, collector);
    }
    if (trackCount != nullptr) {
        *trackCount = 1;
    }
    return 0;
}

} // namespace

highlycomplete_player_handle_t highlycomplete_player_create(
    const char* path,
    int32_t sample_rate,
    int32_t track_index,
    char** error_message
) {
    if (track_index != 0) {
        setError(error_message, "HighlyComplete GSF files expose a single playable track.");
        return nullptr;
    }

    auto* handle = new HighlyCompleteHandle();
    handle->requestedSampleRate = sample_rate > 0 ? sample_rate : 44100;

    if (loadGSFFile(handle, path, error_message) != 0) {
        destroyHandle(handle);
        return nullptr;
    }

    return reinterpret_cast<highlycomplete_player_handle_t>(handle);
}

void highlycomplete_player_destroy(highlycomplete_player_handle_t handle) {
    destroyHandle(reinterpret_cast<HighlyCompleteHandle*>(handle));
}

int32_t highlycomplete_player_configure(
    highlycomplete_player_handle_t handlePointer,
    int32_t loop_seconds,
    int32_t fade_seconds,
    bool uses_native_ending,
    char** error_message
) {
    (void)loop_seconds;
    (void)fade_seconds;
    (void)uses_native_ending;

    auto* handle = reinterpret_cast<HighlyCompleteHandle*>(handlePointer);
    if (handle == nullptr) {
        setError(error_message, "HighlyComplete playback was not initialized.");
        return 1;
    }
    return 0;
}

int32_t highlycomplete_player_read_metadata(
    highlycomplete_player_handle_t handlePointer,
    highlycomplete_metadata_t* metadata,
    char** error_message
) {
    auto* handle = reinterpret_cast<HighlyCompleteHandle*>(handlePointer);
    if (handle == nullptr) {
        setError(error_message, "HighlyComplete playback was not initialized.");
        return 1;
    }
    return copyMetadata(handle->metadata, metadata, error_message);
}

int32_t highlycomplete_player_seek_milliseconds(
    highlycomplete_player_handle_t handlePointer,
    int32_t milliseconds,
    char** error_message
) {
    auto* handle = reinterpret_cast<HighlyCompleteHandle*>(handlePointer);
    if (handle == nullptr) {
        setError(error_message, "HighlyComplete playback was not initialized.");
        return 1;
    }

    int64_t targetFrames = static_cast<int64_t>(
        (static_cast<double>(std::max(milliseconds, 0)) / 1000.0) * handle->requestedSampleRate
    );
    if (targetFrames < handle->playedFrames) {
        if (!initializeCore(handle, error_message)) {
            return 1;
        }
    }

    while (handle->playedFrames < targetFrames) {
        int32_t requested = static_cast<int32_t>(std::min<int64_t>(kAudioChunkFrames, targetFrames - handle->playedFrames));
        int32_t rendered = 0;
        if (renderFrames(handle, requested, nullptr, &rendered, error_message) != 0) {
            return 1;
        }
        if (rendered <= 0) {
            break;
        }
    }

    return 0;
}

int32_t highlycomplete_player_render_s16(
    highlycomplete_player_handle_t handlePointer,
    int32_t requested_frames,
    int16_t* interleaved_samples,
    int32_t* rendered_frames,
    char** error_message
) {
    return renderFrames(
        reinterpret_cast<HighlyCompleteHandle*>(handlePointer),
        requested_frames,
        interleaved_samples,
        rendered_frames,
        error_message
    );
}

int32_t highlycomplete_player_track_ended(highlycomplete_player_handle_t handlePointer) {
    auto* handle = reinterpret_cast<HighlyCompleteHandle*>(handlePointer);
    return handle == nullptr || handle->playbackEnded ? 1 : 0;
}

int32_t highlycomplete_player_played_frames(highlycomplete_player_handle_t handlePointer) {
    auto* handle = reinterpret_cast<HighlyCompleteHandle*>(handlePointer);
    if (handle == nullptr) {
        return 0;
    }
    return static_cast<int32_t>(handle->playedFrames);
}

int32_t highlycomplete_inspect_file(
    const char* path,
    highlycomplete_metadata_t* metadata,
    int32_t* track_count,
    char** error_message
) {
    if (track_count != nullptr) {
        *track_count = 0;
    }
    return inspectGSFFile(path, metadata, track_count, error_message);
}

void highlycomplete_metadata_clear(highlycomplete_metadata_t* metadata) {
    clearMetadata(metadata);
}

void highlycomplete_error_message_free(char* error_message) {
    std::free(error_message);
}
