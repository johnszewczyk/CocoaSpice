#include "psf2_bridge.h"

#include "PsfBase.h"
#include "PsfLoader.h"
#include "PsfPathToken.h"
#include "PsfPlayerAppConfig.h"
#include "PsfTags.h"
#include "PsfVm.h"
#include "sound/SoundHandler.h"
#include "StdStream.h"
#include "StdStreamUtils.h"

#include <algorithm>
#include <condition_variable>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr int kSampleRate = 44100;
constexpr size_t kBufferedFrameCapacity = kSampleRate;
constexpr size_t kPsfWriteBlockSamples = 44 * 2 * 10;

class CaptureSoundHandler final : public CSoundHandler {
public:
    CaptureSoundHandler()
        : m_samples(kBufferedFrameCapacity * 2) {
    }

    void Reset() override {
        std::lock_guard lock(m_mutex);
        m_readIndex = 0;
        m_writeIndex = 0;
        m_sampleCount = 0;
        m_condition.notify_all();
    }

    void Write(int16_t* samples, unsigned int sampleCount, unsigned int sampleRate) override {
        if(sampleRate != kSampleRate) return;
        std::lock_guard lock(m_mutex);
        // HasFreeBuffers is queried by the emulator before every fixed-size
        // write. Never block the VM thread here: Pause and teardown are mailbox
        // operations that must be allowed to reach that same thread.
        if((m_samples.size() - m_sampleCount) < sampleCount) return;
        for(size_t index = 0; index < sampleCount; index++) {
            m_samples[m_writeIndex] = samples[index];
            m_writeIndex = (m_writeIndex + 1) % m_samples.size();
        }
        m_sampleCount += sampleCount;
        m_condition.notify_all();
    }

    bool HasFreeBuffers() override {
        std::lock_guard lock(m_mutex);
        return (m_samples.size() - m_sampleCount) >= kPsfWriteBlockSamples;
    }
    void RecycleBuffers() override {}

    int32_t Read(int16_t* output, int32_t frameCount) {
        std::unique_lock lock(m_mutex);
        m_condition.wait_for(lock, std::chrono::milliseconds(250), [&] {
            return m_sampleCount >= static_cast<size_t>(frameCount) * 2;
        });
        const auto availableFrames = static_cast<int32_t>(m_sampleCount / 2);
        const auto frames = std::min(frameCount, availableFrames);
        const auto samplesToRead = static_cast<size_t>(frames) * 2;
        for(size_t index = 0; index < samplesToRead; index++) {
            output[index] = m_samples[m_readIndex];
            m_readIndex = (m_readIndex + 1) % m_samples.size();
        }
        m_sampleCount -= samplesToRead;
        m_condition.notify_all();
        return frames;
    }

    int64_t BufferedFrames() const {
        std::lock_guard lock(m_mutex);
        return static_cast<int64_t>(m_sampleCount / 2);
    }

private:
    mutable std::mutex m_mutex;
    std::condition_variable m_condition;
    std::vector<int16_t> m_samples;
    size_t m_readIndex = 0;
    size_t m_writeIndex = 0;
    size_t m_sampleCount = 0;
};

struct Metadata {
    CPsfBase::TagMap tags;
    std::map<std::string, std::string> exportedTags;
    int64_t playLengthFrames = 0;

    explicit Metadata(const char* filePath) {
        if(!filePath || !filePath[0]) throw std::runtime_error("PSF2 path is empty");
        auto stream = Framework::CreateInputStdStream(fs::path(filePath).native());
        CPsfBase psfFile(stream);
        if(psfFile.GetVersion() != CPsfBase::VERSION_PLAYSTATION2) {
            throw std::runtime_error("File is not PSF2");
        }
        tags.insert(psfFile.GetTagsBegin(), psfFile.GetTagsEnd());
        exportedTags.insert(tags.begin(), tags.end());
        playLengthFrames = ParseLengthFrames(tags);
    }

    static int64_t ParseLengthFrames(const CPsfBase::TagMap& values) {
        const auto it = values.find("length");
        if(it == values.end()) return 0;
        try {
            const auto wideLength = CPsfPathToken::WidenString(it->second);
            return static_cast<int64_t>(CPsfTags::ConvertTimeString(wideLength.c_str()) * kSampleRate);
        } catch(...) {
            return 0;
        }
    }
};

struct Player {
    CPsfVm vm;
    CaptureSoundHandler* sound = nullptr;
    CPsfBase::TagMap tags;
    std::map<std::string, std::string> exportedTags;
    std::string path;
    int64_t playedFrames = 0;
    int64_t playLengthFrames = 0;
    bool longPlay = false;

    explicit Player(const char* filePath)
        : path(filePath ? filePath : "") {
        if(path.empty()) throw std::runtime_error("PSF2 path is empty");
        const auto token = CPhysicalPsfStreamProvider::GetPathTokenFromFilePath(fs::path(path));
        CPsfLoader::LoadPsf(vm, token, fs::path(), &tags);
        vm.SetSpuHandler([this] {
            sound = new CaptureSoundHandler();
            return sound;
        });
        for(const auto& [key, value] : tags) exportedTags.emplace(key, value);
        playLengthFrames = Metadata::ParseLengthFrames(tags);
        vm.Resume();
    }

    ~Player() { vm.Pause(); }

};

} // namespace

extern "C" void* cocoaspice_psf2_open(const char* path) {
    try { return new Player(path); } catch(...) { return nullptr; }
}

extern "C" void cocoaspice_psf2_close(void* handle) { delete static_cast<Player*>(handle); }

extern "C" int32_t cocoaspice_psf2_read(void* handle, int16_t* output, int32_t frameCount) {
    if(!handle || !output || frameCount <= 0) return -1;
    auto* player = static_cast<Player*>(handle);
    // Some PSF2 drivers stop emitting blocks exactly at the declared length.
    // CocoaSpice owns the post-length fade, so provide silence for the
    // remaining planned frames instead of making the stream end abruptly.
    if(!player->longPlay && player->playLengthFrames > 0 && player->playedFrames >= player->playLengthFrames) {
        std::fill(output, output + (frameCount * 2), 0);
        player->playedFrames += frameCount;
        return frameCount;
    }
    const auto frames = player->sound ? player->sound->Read(output, frameCount) : 0;
    player->playedFrames += frames;
    return frames;
}

extern "C" void cocoaspice_psf2_set_long_play(void* handle, int32_t enabled) {
    if(handle) static_cast<Player*>(handle)->longPlay = enabled != 0;
}

extern "C" int32_t cocoaspice_psf2_seek(void* handle, int64_t frame) {
    if(!handle || frame < 0) return -1;
    auto* player = static_cast<Player*>(handle);
    player->vm.Pause();
    player->vm.Reset();
    const auto token = CPhysicalPsfStreamProvider::GetPathTokenFromFilePath(fs::path(player->path));
    try {
        player->tags.clear();
        CPsfLoader::LoadPsf(player->vm, token, fs::path(), &player->tags);
        player->vm.SetSpuHandler([player] {
            player->sound = new CaptureSoundHandler();
            return player->sound;
        });
        player->vm.Resume();
        player->playedFrames = 0;
        std::vector<int16_t> scratch(2048 * 2);
        while(player->playedFrames < frame) {
            const auto requested = static_cast<int32_t>(std::min<int64_t>(2048, frame - player->playedFrames));
            const auto read = cocoaspice_psf2_read(player, scratch.data(), requested);
            if(read <= 0) break;
        }
        return 0;
    } catch(...) { return -1; }
}

extern "C" void cocoaspice_psf2_set_suspended(void* handle, int32_t suspended) {
    if(!handle) return;
    auto* player = static_cast<Player*>(handle);
    if(suspended) {
        player->vm.Pause();
    } else {
        player->vm.Resume();
    }
}

extern "C" int32_t cocoaspice_psf2_finished(void* handle) {
    if(!handle) return 1;
    auto* player = static_cast<Player*>(handle);
    return !player->longPlay
        && player->playLengthFrames > 0
        && player->playedFrames >= player->playLengthFrames;
}

extern "C" int64_t cocoaspice_psf2_played_frames(void* handle) {
    return handle ? static_cast<Player*>(handle)->playedFrames : 0;
}

extern "C" int64_t cocoaspice_psf2_play_length_frames(void* handle) {
    return handle ? static_cast<Player*>(handle)->playLengthFrames : 0;
}

extern "C" const char* cocoaspice_psf2_tag(void* handle, const char* name) {
    if(!handle || !name) return nullptr;
    auto& tags = static_cast<Player*>(handle)->exportedTags;
    const auto it = tags.find(name);
    return it == tags.end() ? nullptr : it->second.c_str();
}

extern "C" int64_t cocoaspice_psf2_buffered_frames(void* handle) {
    if(!handle) return 0;
    auto* player = static_cast<Player*>(handle);
    return player->sound ? player->sound->BufferedFrames() : 0;
}

extern "C" int64_t cocoaspice_psf2_buffer_capacity_frames(void) {
    return static_cast<int64_t>(kBufferedFrameCapacity);
}

extern "C" void* cocoaspice_psf2_metadata_open(const char* path) {
    try { return new Metadata(path); } catch(...) { return nullptr; }
}

extern "C" void cocoaspice_psf2_metadata_close(void* handle) {
    delete static_cast<Metadata*>(handle);
}

extern "C" int64_t cocoaspice_psf2_metadata_play_length_frames(void* handle) {
    return handle ? static_cast<Metadata*>(handle)->playLengthFrames : 0;
}

extern "C" const char* cocoaspice_psf2_metadata_tag(void* handle, const char* name) {
    if(!handle || !name) return nullptr;
    auto& tags = static_cast<Metadata*>(handle)->exportedTags;
    const auto it = tags.find(name);
    return it == tags.end() ? nullptr : it->second.c_str();
}
