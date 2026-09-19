#include "../include/orbisnav_engine.h"
#include <chrono>
#include <iostream>

namespace orbisnav {

OrbisNavEngine& OrbisNavEngine::instance() {
    static OrbisNavEngine s_engine;
    return s_engine;
}

OrbisNavEngine::OrbisNavEngine()
    : frame_counter_(0),
      cold_boot_duration_ms_(0),
      is_booted_(false) {

    // Wire up platform audio engine drivers
    audio_governor_.initializeDrivers(
        []() {
            // Platform speech flush (QUEUE_FLUSH / stopSpeaking immediate)
        },
        [this](const std::string& text, AudioPriority priority) {
            if (speak_cb_) speak_cb_(text, priority);
        },
        [](bool muted) {
            (void)muted;
            // Platform VAD mic mute
        }
    );

    // Wire up hardware event callbacks
    perception_engine_.registerVadMuteCallback([](bool muted) {
        (void)muted;
    });

    perception_engine_.registerTtsPurgeCallback([this]() {
        audio_governor_.hardInterruptAndPurge();
    });

    perception_engine_.registerEarconCallback([this](const DirectionalEarcon& earcon) {
        if (earcon_cb_) earcon_cb_(earcon);
    });

    perception_engine_.registerHapticCallback([this](const HapticPattern& pattern, float azimuth_deg) {
        if (haptic_cb_) haptic_cb_(pattern, azimuth_deg);
    });

    thermal_governor_.registerTiltCallback([this](const std::string& prompt, const HapticPattern& haptic) {
        if (haptic_cb_) haptic_cb_(haptic, 0.0f);
        audio_governor_.requestSpeech(prompt, AudioPriority::Level1_NavigationCue);
    });

    power_manager_.registerLowBatteryCallback([this](uint32_t battery_percent) {
        (void)battery_percent;
        // Spec Phase 6.1: Unload OCR engines and LLM models from RAM
        model_hydrator_.unloadOcr();
        // Camera stream downclocked to 10 FPS and 4-zone haptics set
    });
}

OrbisNavEngine::~OrbisNavEngine() {
    shutdown();
}

bool OrbisNavEngine::coldBoot() {
    auto start_time = std::chrono::steady_clock::now();

    // 1. Memory Pre-Allocation: Zero-heap static ring buffers in C++ VRAM/RAM (<= 180MB)
    bool mem_ok = ZeroHeapAllocator::instance().initialize();
    if (!mem_ok) {
        std::cerr << "[OrbisNavEngine] Failed to allocate static zero-heap buffers!\n";
        return false;
    }

    // 2. Model Hydration: Load INT8 quantized ONNX models (YOLOv8-Nano, PaddleOCR) directly into memory.
    // 100% offline, zero network calls.
    bool model_ok = model_hydrator_.hydrateModels();
    if (!model_ok) {
        std::cerr << "[OrbisNavEngine] Failed to hydrate INT8 models offline!\n";
        return false;
    }

    // 3. Audio Channel Mutex Setup: Initialize platform audio drivers and mute mic until boot checks complete
    audio_governor_.performColdBootAudioSetup();

    // 4. Boot Confirmation: Fire discrete 50ms dual-pulse haptic cue
    HapticPattern boot_haptic{2, 50, 50, 0.8f};
    if (haptic_cb_) {
        haptic_cb_(boot_haptic, 0.0f);
    }

    auto end_time = std::chrono::steady_clock::now();
    cold_boot_duration_ms_ = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

    is_booted_ = (cold_boot_duration_ms_ < 500);
    return is_booted_;
}

void OrbisNavEngine::ingestYuv420Frame(const uint8_t* y_data, size_t y_size, uint32_t width, uint32_t height, uint64_t timestamp_ns) {
    if (!is_booted_) return;

    frame_counter_++;

    // Check dynamic thermal throttling frame gate
    if (!thermal_governor_.shouldProcessFrame(frame_counter_)) {
        return; // Throttled frame skipped to keep SoC cool
    }

    // Acquire zero-heap ring buffer slot
    auto* slot = ZeroHeapAllocator::instance().acquireWriteFrameSlot();
    if (slot && y_data && y_size <= slot->capacity) {
        std::memcpy(slot->buffer, y_data, y_size);
        slot->size = y_size;
        slot->width = width;
        slot->height = height;
        slot->timestamp_ns = timestamp_ns;
        ZeroHeapAllocator::instance().commitWriteFrameSlot();
    }
}

void OrbisNavEngine::ingestImuSample(float pitch_deg, float roll_deg, float yaw_deg, uint64_t timestamp_ns) {
    ImuOrientation imu{pitch_deg, roll_deg, yaw_deg, timestamp_ns};
    ZeroHeapAllocator::instance().pushImuSample(imu);

    // IMU Orientation Audit: pitch > 30 deg below horizon triggers quiet haptic tick & "Tilt phone up."
    thermal_governor_.updateImuOrientation(imu);
}

void OrbisNavEngine::setSoCTemperature(float temp_celsius) {
    thermal_governor_.updateSoCTemperature(temp_celsius);
}

void OrbisNavEngine::ingestVisionDetections(const std::vector<BoundingBox>& detections, uint64_t timestamp_ns) {
    auto tracked = perception_engine_.processDetections(detections, timestamp_ns);

    // If critical hazard is detected, suspend active conversation
    if (perception_engine_.isCriticalHazardActive()) {
        audio_governor_.suspendForHazard(timestamp_ns);
    }
}

void OrbisNavEngine::configureMapNode(uint32_t id, const std::string& name, float x, float y, const std::string& plaque_label) {
    NavNode node;
    node.id = id;
    node.name = name;
    node.coordinate = {x, y};
    node.is_indoor = true;
    node.plaque_label = plaque_label;
    nav_engine_.addNode(node);
}

void OrbisNavEngine::configureMapEdge(uint32_t from_id, uint32_t to_id, float distance) {
    nav_engine_.addEdge(from_id, to_id, distance);
}

std::vector<uint32_t> OrbisNavEngine::planPath(uint32_t start_id, uint32_t goal_id) {
    return nav_engine_.computeAStarPath(start_id, goal_id);
}

ClockDirection OrbisNavEngine::getNextWaypointClockDirection(uint32_t target_node_id) {
    auto target_node = nav_engine_.getNode(target_node_id);
    if (!target_node.has_value()) {
        return ClockDirection::TwelveOClock;
    }
    PdrState pdr = nav_engine_.getPdrState();
    return nav_engine_.computeClockDirection(pdr.current_pos, pdr.heading_rad, target_node->coordinate);
}

void OrbisNavEngine::ingestPdrStep(float step_length_meters, float heading_rad) {
    nav_engine_.processStep(step_length_meters, heading_rad);
}

bool OrbisNavEngine::ingestOcrPlaqueReading(const std::string& detected_text) {
    if (!thermal_governor_.isOcrEnabled() || power_manager_.isLowPowerMode()) {
        return false; // OCR shed under high heat or low battery
    }
    return nav_engine_.snapToOcrGroundTruth(detected_text, 0.75f);
}

void OrbisNavEngine::startConversationalDialogue(const std::string& query, const std::string& response) {
    audio_governor_.setConversationalState(query, response);
}

void OrbisNavEngine::updateConversationalLifecycle(uint64_t current_timestamp_ns) {
    bool hazard_active = perception_engine_.isCriticalHazardActive();
    uint64_t last_clear_ns = perception_engine_.getLastHazardClearTimestamp();
    audio_governor_.checkAndExecuteAutoResume(current_timestamp_ns, hazard_active, last_clear_ns);
}

void OrbisNavEngine::setBatteryLevel(uint32_t battery_percent) {
    power_manager_.updateBatteryLevel(battery_percent);
}

void OrbisNavEngine::shutdown() {
    power_manager_.executeGracefulShutdown();
    is_booted_ = false;
}

EngineStats OrbisNavEngine::getEngineStats() const {
    EngineStats stats;
    stats.cold_boot_duration_ms = cold_boot_duration_ms_;
    stats.total_memory_allocated_bytes = ZeroHeapAllocator::instance().getTotalAllocatedBytes();
    stats.is_memory_compliant = ZeroHeapAllocator::instance().isWithinBudget();
    stats.is_offline_compliant = model_hydrator_.isFullyOffline();
    stats.current_thermal_band = thermal_governor_.getCurrentBand();
    uint32_t fps = thermal_governor_.getTargetFps();
    if (power_manager_.isLowPowerMode()) {
        fps = std::min(fps, power_manager_.getDownclockedFps());
    }
    stats.current_fps = fps;
    stats.preemption_event_count = perception_engine_.getPreemptionCount();
    stats.last_preemption_latency_ms = perception_engine_.getLastPreemptionLatencyMs();
    stats.is_conversation_suspended = audio_governor_.hasSuspendedContext();
    stats.battery_percent = power_manager_.getBatteryPercent();
    stats.is_low_power_active = power_manager_.isLowPowerMode();
    return stats;
}

} // namespace orbisnav
