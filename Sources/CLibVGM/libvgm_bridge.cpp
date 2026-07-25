#include "libvgm_bridge.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>

#include <zlib.h>

#include "player/playera.hpp"
#include "player/droplayer.hpp"
#include "player/gymplayer.hpp"
#include "player/s98player.hpp"
#include "player/vgmplayer.hpp"
#include "utils/DataLoader.h"
#include "utils/FileLoader.h"
#include "utils/MemoryLoader.h"

namespace {

constexpr int kChannelCount = 2;
constexpr int kBitsPerSample = 16;
constexpr int kSampleBufferFrames = 4096;

struct LibVGMPlayerHandle {
    PlayerA player;
    DATA_LOADER* loader = nullptr;
    UINT8* fileData = nullptr;
    size_t fileSize = 0;
    std::string baseDirectory;
    std::string lastLogMessage;
    bool trackEnded = false;
};

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

void clearMetadata(libvgm_metadata_t* metadata) {
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

uint32_t readLE32(const std::vector<uint8_t>& data, size_t offset) {
    return static_cast<uint32_t>(data[offset])
        | (static_cast<uint32_t>(data[offset + 1]) << 8)
        | (static_cast<uint32_t>(data[offset + 2]) << 16)
        | (static_cast<uint32_t>(data[offset + 3]) << 24);
}

void appendUTF8(std::string& result, uint32_t scalar) {
    if (scalar <= 0x7F) {
        result.push_back(static_cast<char>(scalar));
    } else if (scalar <= 0x7FF) {
        result.push_back(static_cast<char>(0xC0 | (scalar >> 6)));
        result.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
    } else if (scalar <= 0xFFFF) {
        result.push_back(static_cast<char>(0xE0 | (scalar >> 12)));
        result.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3F)));
        result.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
    } else {
        result.push_back(static_cast<char>(0xF0 | (scalar >> 18)));
        result.push_back(static_cast<char>(0x80 | ((scalar >> 12) & 0x3F)));
        result.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3F)));
        result.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
    }
}

bool readUTF16LEString(
    const std::vector<uint8_t>& data,
    size_t end,
    size_t& offset,
    std::string& result
) {
    result.clear();
    while (offset + 2 <= end) {
        uint32_t scalar = static_cast<uint32_t>(data[offset])
            | (static_cast<uint32_t>(data[offset + 1]) << 8);
        offset += 2;
        if (scalar == 0) {
            return true;
        }
        if (scalar >= 0xD800 && scalar <= 0xDBFF) {
            if (offset + 2 > end) return false;
            const uint32_t low = static_cast<uint32_t>(data[offset])
                | (static_cast<uint32_t>(data[offset + 1]) << 8);
            offset += 2;
            if (low < 0xDC00 || low > 0xDFFF) return false;
            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00);
        } else if (scalar >= 0xDC00 && scalar <= 0xDFFF) {
            return false;
        }
        appendUTF8(result, scalar);
    }
    return false;
}

bool readGzipCompatibleFile(const char* path, std::vector<uint8_t>& data) {
    gzFile file = gzopen(path, "rb");
    if (file == nullptr) return false;
    data.clear();
    uint8_t buffer[64 * 1024];
    int readLength = 0;
    while ((readLength = gzread(file, buffer, sizeof(buffer))) > 0) {
        data.insert(data.end(), buffer, buffer + readLength);
    }
    const int closeStatus = gzclose(file);
    return readLength == 0 && closeStatus == Z_OK;
}

std::string fourCCToString(UINT32 value) {
    std::string result(4, '\0');
    result[0] = static_cast<char>((value >> 24) & 0xFF);
    result[1] = static_cast<char>((value >> 16) & 0xFF);
    result[2] = static_cast<char>((value >> 8) & 0xFF);
    result[3] = static_cast<char>(value & 0xFF);
    return result;
}

std::string fallbackSystemDescription(const PLR_SONG_INFO& songInfo) {
    char buffer[64];
    std::snprintf(
        buffer,
        sizeof(buffer),
        "%s v%X.%02X",
        fourCCToString(songInfo.format).c_str(),
        songInfo.fileVerMaj,
        songInfo.fileVerMin
    );
    return std::string(buffer);
}

std::string combineComment(const std::string& comment, const std::string& date, const std::string& encodedBy) {
    std::string result = comment;

    if (!date.empty()) {
        if (!result.empty()) {
            result += " | ";
        }
        result += "Date: " + date;
    }

    if (!encodedBy.empty()) {
        if (!result.empty()) {
            result += " | ";
        }
        result += "Encoded By: " + encodedBy;
    }

    return result;
}

int32_t populateMetadata(PlayerBase* player, libvgm_metadata_t* metadata, char** errorMessage) {
    if (player == nullptr || metadata == nullptr) {
        setError(errorMessage, "libvgm metadata target was not initialized.");
        return 1;
    }

    clearMetadata(metadata);

    std::string title;
    std::string game;
    std::string system;
    std::string artist;
    std::string comment;
    std::string date;
    std::string encodedBy;

    const char* const* tagList = player->GetTags();
    if (tagList != nullptr) {
        for (const char* const* tag = tagList; *tag != nullptr; tag += 2) {
            if (tag[1] == nullptr) {
                continue;
            }

            if (!std::strcmp(tag[0], "TITLE") && title.empty()) {
                title = tag[1];
            } else if (!std::strcmp(tag[0], "GAME") && game.empty()) {
                game = tag[1];
            } else if (!std::strcmp(tag[0], "SYSTEM") && system.empty()) {
                system = tag[1];
            } else if (!std::strcmp(tag[0], "ARTIST") && artist.empty()) {
                artist = tag[1];
            } else if (!std::strcmp(tag[0], "COMMENT") && comment.empty()) {
                comment = tag[1];
            } else if (!std::strcmp(tag[0], "DATE") && date.empty()) {
                date = tag[1];
            } else if (!std::strcmp(tag[0], "ENCODED_BY") && encodedBy.empty()) {
                encodedBy = tag[1];
            }
        }
    }

    PLR_SONG_INFO songInfo;
    if (player->GetSongInfo(songInfo) != 0x00) {
        setError(errorMessage, "libvgm could not read song information.");
        return 1;
    }

    if (system.empty()) {
        system = fallbackSystemDescription(songInfo);
    }

    const UINT32 loopStartTick = songInfo.loopTick;
    const UINT32 loopTicks = player->GetLoopTicks();
    const double tickToMilliseconds = 1000.0;

    metadata->title = duplicateCString(title);
    metadata->game = duplicateCString(game);
    metadata->system = duplicateCString(system);
    metadata->artist = duplicateCString(artist);
    metadata->comment = duplicateCString(combineComment(comment, date, encodedBy));
    metadata->intro_length_ms =
        (loopStartTick != static_cast<UINT32>(-1) && loopTicks > 0)
            ? static_cast<int32_t>(player->Tick2Second(loopStartTick) * tickToMilliseconds)
            : 0;
    metadata->loop_length_ms =
        loopTicks > 0
            ? static_cast<int32_t>(player->Tick2Second(loopTicks) * tickToMilliseconds)
            : 0;
    metadata->play_length_ms =
        static_cast<int32_t>(player->Tick2Second(player->GetTotalPlayTicks(1)) * tickToMilliseconds);
    metadata->fade_length_ms = 0;
    metadata->track_count = 1;

    return 0;
}

UINT8 playbackEventCallback(PlayerBase* player, void* userParam, UINT8 eventType, void* eventParam) {
    LibVGMPlayerHandle* handle = static_cast<LibVGMPlayerHandle*>(userParam);
    if (handle == nullptr) {
        return 0x00;
    }

    switch (eventType) {
    case PLREVT_END:
        handle->trackEnded = true;
        break;
    default:
        break;
    }

    return 0x00;
}

void playbackLogCallback(
    void* userParam,
    PlayerBase* player,
    UINT8 level,
    UINT8 srcType,
    const char* srcTag,
    const char* message
) {
    LibVGMPlayerHandle* handle = static_cast<LibVGMPlayerHandle*>(userParam);
    if (handle != nullptr && message != nullptr) {
        handle->lastLogMessage = message;
    }
}

DATA_LOADER* fileRequestCallback(void* userParam, PlayerBase* player, const char* fileName) {
    LibVGMPlayerHandle* handle = static_cast<LibVGMPlayerHandle*>(userParam);
    if (fileName == nullptr || handle == nullptr) {
        return nullptr;
    }

    std::string resolvedPath;
    if (fileName[0] == '/') {
        resolvedPath = fileName;
    } else if (!handle->baseDirectory.empty()) {
        resolvedPath = handle->baseDirectory + "/" + fileName;
    } else {
        resolvedPath = fileName;
    }

    DATA_LOADER* loader = FileLoader_Init(resolvedPath.c_str());
    if (loader == nullptr) {
        return nullptr;
    }

    if (DataLoader_Load(loader) == 0x00) {
        return loader;
    }

    DataLoader_Deinit(loader);
    return nullptr;
}

void destroyHandle(LibVGMPlayerHandle* handle) {
    if (handle == nullptr) {
        return;
    }

    handle->player.UnloadFile();
    if (handle->loader != nullptr) {
        DataLoader_Deinit(handle->loader);
        handle->loader = nullptr;
    }
    std::free(handle->fileData);
    handle->fileData = nullptr;
    delete handle;
}

int32_t configurePlayer(
    LibVGMPlayerHandle* handle,
    int32_t sampleRate,
    int32_t trackIndex,
    char** errorMessage
) {
    if (trackIndex != 0) {
        setError(errorMessage, "libvgm files currently expose a single playable track.");
        return 1;
    }

    if (handle->player.SetOutputSettings(sampleRate, kChannelCount, kBitsPerSample, kSampleBufferFrames) != 0x00) {
        setError(errorMessage, "libvgm rejected the requested output format.");
        return 1;
    }

    handle->player.RegisterPlayerEngine(new VGMPlayer);
    handle->player.RegisterPlayerEngine(new S98Player);
    handle->player.RegisterPlayerEngine(new DROPlayer);
    handle->player.RegisterPlayerEngine(new GYMPlayer);
    handle->player.SetEventCallback(playbackEventCallback, handle);
    handle->player.SetFileReqCallback(fileRequestCallback, handle);
    handle->player.SetLogCallback(playbackLogCallback, handle);
    return 0;
}

bool inflateGzipPayload(
    const UINT8* compressedData,
    size_t compressedSize,
    std::vector<UINT8>& decompressedData,
    char** errorMessage
) {
    z_stream stream {};
    stream.next_in = const_cast<Bytef*>(reinterpret_cast<const Bytef*>(compressedData));
    stream.avail_in = static_cast<uInt>(compressedSize);
    if (inflateInit2(&stream, 16 + MAX_WBITS) != Z_OK) {
        setError(errorMessage, "libvgm could not initialize VGZ decompression.");
        return false;
    }

    decompressedData.resize(64 * 1024);
    int status = Z_OK;
    while (status == Z_OK) {
        if (stream.total_out == decompressedData.size()) {
            decompressedData.resize(decompressedData.size() * 2);
        }
        stream.next_out = reinterpret_cast<Bytef*>(decompressedData.data() + stream.total_out);
        stream.avail_out = static_cast<uInt>(decompressedData.size() - stream.total_out);
        status = inflate(&stream, Z_NO_FLUSH);
    }
    inflateEnd(&stream);

    if (status != Z_STREAM_END) {
        setError(errorMessage, "libvgm could not decompress this VGZ file.");
        return false;
    }
    decompressedData.resize(stream.total_out);
    return true;
}

int32_t loadFileIntoMemory(LibVGMPlayerHandle* handle, const char* path, char** errorMessage) {
    std::FILE* file = std::fopen(path, "rb");
    if (file == nullptr) {
        setError(errorMessage, "libvgm could not open the requested file.");
        return 1;
    }

    if (std::fseek(file, 0, SEEK_END) != 0) {
        std::fclose(file);
        setError(errorMessage, "libvgm could not seek the requested file.");
        return 1;
    }

    long fileSize = std::ftell(file);
    if (fileSize < 0) {
        std::fclose(file);
        setError(errorMessage, "libvgm could not determine the file size.");
        return 1;
    }

    if (std::fseek(file, 0, SEEK_SET) != 0) {
        std::fclose(file);
        setError(errorMessage, "libvgm could not rewind the requested file.");
        return 1;
    }

    handle->fileData = static_cast<UINT8*>(std::malloc(static_cast<size_t>(fileSize)));
    if (handle->fileData == nullptr) {
        std::fclose(file);
        setError(errorMessage, "libvgm could not allocate the file buffer.");
        return 1;
    }

    size_t bytesRead = std::fread(handle->fileData, 1, static_cast<size_t>(fileSize), file);
    std::fclose(file);
    if (bytesRead != static_cast<size_t>(fileSize)) {
        setError(errorMessage, "libvgm could not read the full file into memory.");
        return 1;
    }

    const bool isGzip = fileSize >= 2 && handle->fileData[0] == 0x1F && handle->fileData[1] == 0x8B;
    if (isGzip) {
        std::vector<UINT8> decompressedData;
        if (!inflateGzipPayload(handle->fileData, static_cast<size_t>(fileSize), decompressedData, errorMessage)) {
            return 1;
        }
        UINT8* decodedData = static_cast<UINT8*>(std::malloc(decompressedData.size()));
        if (decodedData == nullptr) {
            setError(errorMessage, "libvgm could not allocate decompressed VGZ data.");
            return 1;
        }
        std::memcpy(decodedData, decompressedData.data(), decompressedData.size());
        std::free(handle->fileData);
        handle->fileData = decodedData;
        fileSize = static_cast<long>(decompressedData.size());
    }

    handle->fileSize = static_cast<size_t>(fileSize);
    handle->loader = MemoryLoader_Init(handle->fileData, static_cast<unsigned int>(handle->fileSize));
    if (handle->loader == nullptr) {
        setError(errorMessage, "libvgm could not initialize its memory loader.");
        return 1;
    }

    DataLoader_SetPreloadBytes(handle->loader, 0x100);
    if (DataLoader_Load(handle->loader) != 0x00) {
        setError(errorMessage, "libvgm could not preload the track data.");
        return 1;
    }

    const UINT8 loadStatus = handle->player.LoadFile(handle->loader);
    if (loadStatus != 0x00) {
        char signature[16] {};
        std::snprintf(
            signature,
            sizeof(signature),
            "%02X%02X%02X%02X",
            handle->fileSize > 0 ? handle->fileData[0] : 0,
            handle->fileSize > 1 ? handle->fileData[1] : 0,
            handle->fileSize > 2 ? handle->fileData[2] : 0,
            handle->fileSize > 3 ? handle->fileData[3] : 0
        );
        const std::string detail = handle->lastLogMessage.empty()
            ? "libvgm could not decode this VGM-family file (status " + std::to_string(loadStatus) + ", header " + signature + ")."
            : "libvgm could not decode this VGM-family file: " + handle->lastLogMessage;
        setError(errorMessage, detail);
        return 1;
    }

    if (handle->player.Start() != 0x00) {
        setError(errorMessage, "libvgm failed to start playback.");
        return 1;
    }

    handle->trackEnded = false;
    return 0;
}

} // namespace

libvgm_player_handle_t libvgm_player_create(
    const char* path,
    int32_t sample_rate,
    int32_t track_index,
    char** error_message
) {
    if (path == nullptr) {
        setError(error_message, "libvgm needs a file path.");
        return nullptr;
    }

    LibVGMPlayerHandle* handle = new LibVGMPlayerHandle();
    std::string inputPath(path);
    size_t slashIndex = inputPath.find_last_of('/');
    if (slashIndex != std::string::npos) {
        handle->baseDirectory = inputPath.substr(0, slashIndex);
    }

    if (configurePlayer(handle, sample_rate, track_index, error_message) != 0 ||
        loadFileIntoMemory(handle, path, error_message) != 0) {
        destroyHandle(handle);
        return nullptr;
    }

    return reinterpret_cast<libvgm_player_handle_t>(handle);
}

void libvgm_player_destroy(libvgm_player_handle_t handle) {
    destroyHandle(reinterpret_cast<LibVGMPlayerHandle*>(handle));
}

int32_t libvgm_player_configure(
    libvgm_player_handle_t handlePointer,
    int32_t loop_seconds,
    int32_t fade_seconds,
    bool uses_native_ending,
    char** error_message
) {
    LibVGMPlayerHandle* handle = reinterpret_cast<LibVGMPlayerHandle*>(handlePointer);
    if (handle == nullptr) {
        setError(error_message, "libvgm playback was not initialized.");
        return 1;
    }

    PlayerA::Config config = handle->player.GetConfiguration();
    config.masterVol = 0x10000;
    config.ignoreVolGain = false;
    config.chnInvert = 0x00;
    config.loopCount = uses_native_ending ? 1 : 0;
    config.fadeSmpls = 0;
    config.endSilenceSmpls = 0;
    config.pbSpeed = 1.0;
    handle->player.SetConfiguration(config);
    handle->trackEnded = false;

    (void)loop_seconds;
    (void)fade_seconds;
    return 0;
}

int32_t libvgm_player_read_metadata(
    libvgm_player_handle_t handlePointer,
    libvgm_metadata_t* metadata,
    char** error_message
) {
    LibVGMPlayerHandle* handle = reinterpret_cast<LibVGMPlayerHandle*>(handlePointer);
    if (handle == nullptr) {
        setError(error_message, "libvgm playback was not initialized.");
        return 1;
    }

    return populateMetadata(handle->player.GetPlayer(), metadata, error_message);
}

int32_t libvgm_player_seek_milliseconds(
    libvgm_player_handle_t handlePointer,
    int32_t milliseconds,
    char** error_message
) {
    LibVGMPlayerHandle* handle = reinterpret_cast<LibVGMPlayerHandle*>(handlePointer);
    if (handle == nullptr) {
        setError(error_message, "libvgm playback was not initialized.");
        return 1;
    }

    UINT32 samplePosition = static_cast<UINT32>((static_cast<double>(milliseconds) / 1000.0) * handle->player.GetSampleRate());
    if (handle->player.Seek(PLAYPOS_SAMPLE, samplePosition) != 0x00) {
        setError(error_message, "libvgm could not seek to the requested position.");
        return 1;
    }

    handle->trackEnded = false;
    return 0;
}

int32_t libvgm_player_render_s16(
    libvgm_player_handle_t handlePointer,
    int32_t requested_frames,
    int16_t* interleaved_samples,
    int32_t* rendered_frames,
    char** error_message
) {
    LibVGMPlayerHandle* handle = reinterpret_cast<LibVGMPlayerHandle*>(handlePointer);
    if (handle == nullptr || interleaved_samples == nullptr || rendered_frames == nullptr) {
        setError(error_message, "libvgm render arguments were incomplete.");
        return 1;
    }

    const UINT32 bytesPerFrame = kChannelCount * (kBitsPerSample / 8);
    UINT32 renderedBytes = handle->player.Render(static_cast<UINT32>(requested_frames) * bytesPerFrame, interleaved_samples);
    *rendered_frames = static_cast<int32_t>(renderedBytes / bytesPerFrame);
    if (handle->player.GetState() & PLAYSTATE_FIN) {
        handle->trackEnded = true;
    }
    return 0;
}

int32_t libvgm_player_track_ended(libvgm_player_handle_t handlePointer) {
    LibVGMPlayerHandle* handle = reinterpret_cast<LibVGMPlayerHandle*>(handlePointer);
    if (handle == nullptr) {
        return 1;
    }

    if (handle->trackEnded || (handle->player.GetState() & PLAYSTATE_FIN)) {
        return 1;
    }
    return 0;
}

int32_t libvgm_player_played_frames(libvgm_player_handle_t handlePointer) {
    LibVGMPlayerHandle* handle = reinterpret_cast<LibVGMPlayerHandle*>(handlePointer);
    if (handle == nullptr) {
        return 0;
    }

    return static_cast<int32_t>(handle->player.GetCurPos(PLAYPOS_SAMPLE));
}

int32_t libvgm_inspect_file(
    const char* path,
    libvgm_metadata_t* metadata,
    int32_t* track_count,
    char** error_message
) {
    if (track_count != nullptr) {
        *track_count = 0;
    }

    libvgm_player_handle_t handle = libvgm_player_create(path, 44100, 0, error_message);
    if (handle == nullptr) {
        return 1;
    }

    int32_t status = libvgm_player_read_metadata(handle, metadata, error_message);
    if (status == 0 && track_count != nullptr) {
        *track_count = 1;
    }

    libvgm_player_destroy(handle);
    return status;
}

int32_t libvgm_read_vgm_metadata_fast(
    const char* path,
    libvgm_metadata_t* metadata
) {
    if (path == nullptr || metadata == nullptr) return 1;

    std::vector<uint8_t> data;
    if (!readGzipCompatibleFile(path, data)
        || data.size() < 0x40
        || std::memcmp(data.data(), "Vgm ", 4) != 0) {
        return 1;
    }

    const uint32_t gd3RelativeOffset = readLE32(data, 0x14);
    if (gd3RelativeOffset == 0) return 2;
    const uint64_t gd3Offset64 = 0x14ULL + gd3RelativeOffset;
    if (gd3Offset64 + 0x0C > data.size()) return 1;
    const size_t gd3Offset = static_cast<size_t>(gd3Offset64);
    if (std::memcmp(data.data() + gd3Offset, "Gd3 ", 4) != 0) return 1;

    const uint32_t gd3Version = readLE32(data, gd3Offset + 0x04);
    const uint32_t gd3Length = readLE32(data, gd3Offset + 0x08);
    const uint64_t payloadEnd64 = static_cast<uint64_t>(gd3Offset) + 0x0C + gd3Length;
    if (gd3Version < 0x100 || gd3Version >= 0x200 || payloadEnd64 > data.size()) return 1;

    const size_t payloadEnd = static_cast<size_t>(payloadEnd64);
    size_t offset = gd3Offset + 0x0C;
    std::vector<std::string> fields(11);
    for (std::string& field : fields) {
        if (!readUTF16LEString(data, payloadEnd, offset, field)) return 1;
    }

    clearMetadata(metadata);
    const uint32_t totalSamples = readLE32(data, 0x18);
    const uint32_t loopRelativeOffset = readLE32(data, 0x1C);
    const uint32_t loopSamples = readLE32(data, 0x20);
    const bool hasLoop = loopRelativeOffset != 0 && loopSamples > 0 && loopSamples <= totalSamples;
    const auto milliseconds = [](uint32_t samples) -> int32_t {
        return static_cast<int32_t>((static_cast<uint64_t>(samples) * 1000) / 44100);
    };

    metadata->title = duplicateCString(fields[0]);
    metadata->game = duplicateCString(fields[2]);
    metadata->system = duplicateCString(fields[4]);
    metadata->artist = duplicateCString(fields[6]);
    metadata->comment = duplicateCString(combineComment(fields[10], fields[8], fields[9]));
    metadata->intro_length_ms = hasLoop ? milliseconds(totalSamples - loopSamples) : 0;
    metadata->loop_length_ms = hasLoop ? milliseconds(loopSamples) : 0;
    metadata->play_length_ms = milliseconds(totalSamples);
    metadata->fade_length_ms = 0;
    metadata->track_count = 1;
    return 0;
}

void libvgm_metadata_clear(libvgm_metadata_t* metadata) {
    clearMetadata(metadata);
}

void libvgm_error_message_free(char* error_message) {
    std::free(error_message);
}
