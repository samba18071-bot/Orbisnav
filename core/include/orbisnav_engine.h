#ifndef ORBISNAV_ENGINE_H
#define ORBISNAV_ENGINE_H

#include "orbisnav_types.h"
#include "zero_heap_allocator.h"
#include "model_hydrator.h"
#include "thermal_governor.h"
#include "perception_preemption.h"
#include "navigation_engine.h"
#include "audio_governor.h"
#include "power_and_lifecycle.h"

#include <memory>
#include <string>
#include <vector>

namespace orbisnav {

struct EngineStats {
    uint64_t cold_boot_duration_ms{0};
    size_t total_memory_allocated_bytes{0};
    bool is_memory_compliant{false};
    bool is_offline_compliant{false};
    ThermalBand current_thermal_band{ThermalBand::Nominal_Under40C};
    uint32_t current_fps{30};
    uint32_t preemption_event_count{0};
    float last_preemption_latency_ms{0.0f};
    bool is_conversation_suspended{false};
    uint32_t battery_percent{100};
    bool is_low_power_active{false};
};

class OrbisNavEngine {
public:
    static OrbisNavEngine& instance();

    // PHASE 1: Cold Boot & On-Device Initialization (<500ms)
    bool coldBoot();

    // PHASE 2: Sensor Ingestion & Thermal Governance
    void ingestYuv420Frame(const uint8_t* y_data, size_t y_size, uint32_t width, uint32_t height, uint64_t timestamp_ns);
    void ingestImuSample(float pitch_deg, float roll_deg, float yaw_deg, uint64_t timestamp_ns);
    void setSoCTemperature(float temp_celsius);

    // PHASE 3: Real-Time Perception & Hazard Preemption
    void ingestVisionDetections(const std::vector<BoundingBox>& detections, uint64_t timestamp_ns);

    // PHASE 4: A* Navigation & PDR Drift Re-Anchoring
    void configureMapNode(uint32_t id, const std::string& name, float x, float y, const std::string& plaque_label);
    void configureMapEdge(uint32_t from_id, uint32_t to_id, float distance);
    std::vector<uint32_t> planPath(uint32_t start_id, uint32_t goal_id);
    ClockDirection getNextWaypointClockDirection(uint32_t target_node_id);
    void ingestPdrStep(float step_length_meters, float heading_rad);
    bool ingestOcrPlaqueReading(const std::string& detected_text);

    // PHASE 5: Conversational Suspension & Auto-Resumption
    void startConversationalDialogue(const std::string& query, const std::string& response);
    void updateConversationalLifecycle(uint64_t current_timestamp_ns);

    // PHASE 6: Power Saver & Termination
    void setBatteryLevel(uint32_t battery_percent);
    void shutdown();

    // Subsystem accessors
    ZeroHeapAllocator& getAllocator() { return ZeroHeapAllocator::instance(); }
    ModelHydrator& getModelHydrator() { return model_hydrator_; }
    ThermalGovernor& getThermalGovernor() { return thermal_governor_; }
    PerceptionPreemptionEngine& getPerceptionEngine() { return perception_engine_; }
    NavigationEngine& getNavigationEngine() { return nav_engine_; }
    AudioGovernor& getAudioGovernor() { return audio_governor_; }
    PowerAndLifecycleManager& getPowerManager() { return power_manager_; }

    // System Telemetry
    EngineStats getEngineStats() const;

    // Platform Callbacks
    void registerSpeechCallback(AudioGovernor::PlatformSpeakCallback cb) { speak_cb_ = cb; }
    void registerHapticCallback(PerceptionPreemptionEngine::HapticCallback cb) { haptic_cb_ = cb; }
    void registerEarconCallback(PerceptionPreemptionEngine::EarconCallback cb) { earcon_cb_ = cb; }

private:
    OrbisNavEngine();
    ~OrbisNavEngine();
    OrbisNavEngine(const OrbisNavEngine&) = delete;
    OrbisNavEngine& operator=(const OrbisNavEngine&) = delete;

    ModelHydrator model_hydrator_;
    ThermalGovernor thermal_governor_;
    PerceptionPreemptionEngine perception_engine_;
    NavigationEngine nav_engine_;
    AudioGovernor audio_governor_;
    PowerAndLifecycleManager power_manager_;

    uint64_t frame_counter_{0};
    uint64_t cold_boot_duration_ms_{0};
    bool is_booted_{false};

    AudioGovernor::PlatformSpeakCallback speak_cb_;
    PerceptionPreemptionEngine::HapticCallback haptic_cb_;
    PerceptionPreemptionEngine::EarconCallback earcon_cb_;
};

} // namespace orbisnav

#endif // ORBISNAV_ENGINE_H
