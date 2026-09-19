#ifndef AUDIO_GOVERNOR_H
#define AUDIO_GOVERNOR_H

#include "orbisnav_types.h"
#include <stack>
#include <functional>
#include <string>
#include <mutex>

namespace orbisnav {

class AudioGovernor {
public:
    // Platform speech engine driver callbacks
    // Android: TextToSpeech.QUEUE_FLUSH
    // iOS: AVSpeechSynthesizer.stopSpeaking(at: .immediate)
    using PlatformFlushCallback = std::function<void()>;
    using PlatformSpeakCallback = std::function<void(const std::string& text, AudioPriority priority)>;
    using VadMicrophoneCallback = std::function<void(bool muted)>;

    AudioGovernor();
    ~AudioGovernor();

    void initializeDrivers(PlatformFlushCallback flush_cb,
                           PlatformSpeakCallback speak_cb,
                           VadMicrophoneCallback mic_cb);

    // Boot Audio Mutex Setup (Phase 1.3)
    void performColdBootAudioSetup();

    // Priority Speech Request
    bool requestSpeech(const std::string& text, AudioPriority priority);

    // Hard Interrupt / Speech Purge (Phase 3.3)
    void hardInterruptAndPurge();

    // Phase 5.1: Conversational Dialogue active at Level 3
    void setConversationalState(const std::string& user_query, const std::string& partial_response);

    // Phase 5.2: Hazard Suspension
    // Pushes current state to ConversationContextStack, halts speech & VAD, plays Level 0 alert
    void suspendForHazard(uint64_t timestamp_ns = 0);

    // Phase 5.3: Path-Clear Auto-Resume
    // Called with timestamp and hazard status; if clear >= 1.5s, pops and resumes
    bool checkAndExecuteAutoResume(uint64_t current_timestamp_ns, bool hazard_active, uint64_t last_hazard_clear_ns);

    // Stack inspection
    bool hasSuspendedContext() const;
    size_t getContextStackDepth() const;

    // Platform state queries
    bool isMicrophoneMuted() const { return microphone_muted_; }
    AudioPriority getCurrentPriority() const { return active_priority_; }
    bool isSpeechPlaying() const { return speech_playing_; }
    void notifySpeechCompleted();

private:
    std::mutex audio_mutex_;
    PlatformFlushCallback flush_cb_;
    PlatformSpeakCallback speak_cb_;
    VadMicrophoneCallback mic_cb_;

    bool microphone_muted_{true};
    bool speech_playing_{false};
    AudioPriority active_priority_{AudioPriority::Level3_Conversational};

    ConversationContext active_conversation_;
    std::stack<ConversationContext> context_stack_;

    static constexpr uint64_t PATH_CLEAR_RESUME_DELAY_NS = 1500000000ULL; // 1.5 seconds
    static constexpr uint64_t CONTEXT_EXPIRATION_TTL_NS   = 45000000000ULL; // 45-second context expiration
    bool auto_resume_pending_{false};
};

} // namespace orbisnav

#endif // AUDIO_GOVERNOR_H
