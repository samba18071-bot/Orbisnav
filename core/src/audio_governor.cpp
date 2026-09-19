#include "../include/audio_governor.h"
#include <iostream>

namespace orbisnav {

AudioGovernor::AudioGovernor()
    : microphone_muted_(true),
      active_priority_(AudioPriority::Level3_Conversational),
      auto_resume_pending_(false) {}

AudioGovernor::~AudioGovernor() = default;

void AudioGovernor::initializeDrivers(PlatformFlushCallback flush_cb,
                                     PlatformSpeakCallback speak_cb,
                                     VadMicrophoneCallback mic_cb) {
    std::lock_guard<std::mutex> lock(audio_mutex_);
    flush_cb_ = flush_cb;
    speak_cb_ = speak_cb;
    mic_cb_ = mic_cb;
}

void AudioGovernor::performColdBootAudioSetup() {
    std::lock_guard<std::mutex> lock(audio_mutex_);

    // Spec Phase 1.3:
    // "Audio Channel Mutex Setup: Initialize platform audio drivers
    // (TextToSpeech.QUEUE_FLUSH on Android, AVSpeechSynthesizer.stopSpeaking(at: .immediate) on iOS).
    // Mute microphone input until boot checks complete."
    if (flush_cb_) {
        flush_cb_();
    }

    microphone_muted_ = true;
    if (mic_cb_) {
        mic_cb_(true); // Mute mic
    }
}

void AudioGovernor::hardInterruptAndPurge() {
    std::lock_guard<std::mutex> lock(audio_mutex_);

    // Phase 3.3: Purge active speech buffers via stopTTS()
    if (flush_cb_) {
        flush_cb_();
    }

    // Mute active microphone (VAD) instantly
    microphone_muted_ = true;
    speech_playing_ = false;
    if (mic_cb_) {
        mic_cb_(true);
    }

    active_priority_ = AudioPriority::Level0_HazardAlert;
}

bool AudioGovernor::requestSpeech(const std::string& text, AudioPriority priority) {
    std::lock_guard<std::mutex> lock(audio_mutex_);

    // If higher priority audio is currently actively playing, reject lower priority
    // Note: lower numerical enum value represents higher priority (Level 0 > Level 1 > Level 2 > Level 3)
    if (speech_playing_ && static_cast<uint8_t>(priority) > static_cast<uint8_t>(active_priority_)) {
        return false;
    }

    // If higher or equal priority, preempt current speech
    if (flush_cb_) {
        flush_cb_();
    }

    active_priority_ = priority;
    speech_playing_ = true;
    if (speak_cb_) {
        speak_cb_(text, priority);
    }
    return true;
}

void AudioGovernor::notifySpeechCompleted() {
    std::lock_guard<std::mutex> lock(audio_mutex_);
    speech_playing_ = false;
    active_priority_ = AudioPriority::Level3_Conversational;
}

void AudioGovernor::setConversationalState(const std::string& user_query, const std::string& partial_response) {
    std::lock_guard<std::mutex> lock(audio_mutex_);
    active_conversation_.user_query = user_query;
    active_conversation_.partial_llm_response = partial_response;
    active_conversation_.is_active = true;
    active_priority_ = AudioPriority::Level3_Conversational;
    
    // Unmute mic for conversational listening unless explicitly muted
    microphone_muted_ = false;
    if (mic_cb_) {
        mic_cb_(false);
    }
}

void AudioGovernor::suspendForHazard(uint64_t timestamp_ns) {
    std::lock_guard<std::mutex> lock(audio_mutex_);

    // Phase 5.2 / Step 4.2: Hazard Suspension:
    // 1. Push current LLM query/response state to ConversationContextStack with 45s TTL
    if (active_conversation_.is_active) {
        if (timestamp_ns > 0) {
            active_conversation_.suspended_timestamp_ns = timestamp_ns;
        } else {
            active_conversation_.suspended_timestamp_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
                              std::chrono::steady_clock::now().time_since_epoch()).count();
        }
        context_stack_.push(active_conversation_);
        active_conversation_.is_active = false;
        auto_resume_pending_ = true;
    }

    // 2. Halt speech and VAD listening
    if (flush_cb_) {
        flush_cb_();
    }
    microphone_muted_ = true;
    speech_playing_ = false;
    if (mic_cb_) {
        mic_cb_(true);
    }

    // 3. Set priority to Level 0
    active_priority_ = AudioPriority::Level0_HazardAlert;
}

bool AudioGovernor::checkAndExecuteAutoResume(uint64_t current_timestamp_ns, bool hazard_active, uint64_t last_hazard_clear_ns) {
    std::lock_guard<std::mutex> lock(audio_mutex_);

    if (!auto_resume_pending_ || context_stack_.empty()) {
        return false;
    }

    if (hazard_active) {
        return false; // Still obstructed
    }

    // Step 4.3: Path-Clear Auto-Resume:
    // When vision sensors verify the path is clear for >= 1.5 continuous seconds
    if (last_hazard_clear_ns > 0 && current_timestamp_ns >= last_hazard_clear_ns &&
        (current_timestamp_ns - last_hazard_clear_ns >= PATH_CLEAR_RESUME_DELAY_NS)) {

        // Pop context from stack
        ConversationContext resumed_ctx = context_stack_.top();
        context_stack_.pop();
        auto_resume_pending_ = false;

        // Unmute VAD microphone
        microphone_muted_ = false;
        if (mic_cb_) {
            mic_cb_(false);
        }

        active_priority_ = AudioPriority::Level3_Conversational;

        // Check 45-second expiration timer (Step 4.2)
        bool is_expired = false;
        if (resumed_ctx.suspended_timestamp_ns > 0 &&
            current_timestamp_ns >= resumed_ctx.suspended_timestamp_ns &&
            (current_timestamp_ns - resumed_ctx.suspended_timestamp_ns > CONTEXT_EXPIRATION_TTL_NS)) {
            is_expired = true;
        }

        std::string resumption_prompt;
        if (is_expired) {
            // Discard stale context payload
            active_conversation_.is_active = false;
            resumption_prompt = "Path clear.";
        } else {
            active_conversation_ = resumed_ctx;
            active_conversation_.is_active = true;
            // Speak resumption string: "Path clear. Continuing..." followed by saved context
            resumption_prompt = "Path clear. Continuing... " + resumed_ctx.partial_llm_response;
        }

        if (speak_cb_) {
            speak_cb_(resumption_prompt, AudioPriority::Level3_Conversational);
        }

        return true;
    }

    return false;
}

bool AudioGovernor::hasSuspendedContext() const {
    return !context_stack_.empty();
}

size_t AudioGovernor::getContextStackDepth() const {
    return context_stack_.size();
}

} // namespace orbisnav
