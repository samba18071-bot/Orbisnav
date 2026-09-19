#ifndef PERCEPTION_PREEMPTION_H
#define PERCEPTION_PREEMPTION_H

#include "orbisnav_types.h"
#include <vector>
#include <map>
#include <deque>
#include <functional>
#include <chrono>

namespace orbisnav {

// ByteTrack simple Kalman state for 3D position & velocity
struct KalmanTrack {
    uint32_t track_id{0};
    ObstacleClass class_id{ObstacleClass::Unknown};
    BoundingBox bbox;
    Vector3 position{0.0f, 0.0f, 0.0f}; // x: right, y: up, z: forward (meters)
    Vector3 velocity{0.0f, 0.0f, 0.0f}; // m/s
    float distance{0.0f};
    float ttc_seconds{999.0f};
    uint64_t last_updated_ns{0};
    uint32_t hits{0};
    uint32_t time_since_update{0};
};

// Debounce record for 800ms sliding window
struct DebounceRecord {
    uint64_t timestamp_ns{0};
    BoundingBox bbox;
    ObstacleClass class_id;
};

class PerceptionPreemptionEngine {
public:
    // Callbacks for hardware preemption
    using VadMuteCallback = std::function<void(bool muted)>;
    using TtsPurgeCallback = std::function<void()>;
    using EarconCallback = std::function<void(const DirectionalEarcon& earcon)>;
    using HapticCallback = std::function<void(const HapticPattern& pattern, float azimuth_deg)>;

    PerceptionPreemptionEngine();
    ~PerceptionPreemptionEngine();

    void registerVadMuteCallback(VadMuteCallback cb) { vad_mute_cb_ = cb; }
    void registerTtsPurgeCallback(TtsPurgeCallback cb) { tts_purge_cb_ = cb; }
    void registerEarconCallback(EarconCallback cb) { earcon_cb_ = cb; }
    void registerHapticCallback(HapticCallback cb) { haptic_cb_ = cb; }

    // Ingest detected bounding boxes from YOLOv8-Nano
    std::vector<TrackedObstacle> processDetections(
        const std::vector<BoundingBox>& detections,
        uint64_t frame_timestamp_ns);

    // 800ms sliding window debounce check
    bool shouldDebounce(const BoundingBox& bbox, uint64_t timestamp_ns);

    // Check if critical hazard is currently present
    bool isCriticalHazardActive() const { return critical_hazard_active_; }
    uint64_t getLastHazardClearTimestamp() const { return last_hazard_clear_ns_; }

    // Query preemption stats
    uint32_t getPreemptionCount() const { return preemption_count_; }
    float getLastPreemptionLatencyMs() const { return last_preemption_latency_ms_; }

private:
    std::vector<KalmanTrack> tracks_;
    uint32_t next_track_id_{1};

    // 800ms sliding window debounce records
    std::deque<DebounceRecord> debounce_window_;
    static constexpr uint64_t DEBOUNCE_WINDOW_NS = 800000000ULL; // 800ms

    // Preemption triggers
    bool critical_hazard_active_{false};
    uint64_t last_hazard_clear_ns_{0};
    uint32_t preemption_count_{0};
    float last_preemption_latency_ms_{0.0f};

    // Callbacks
    VadMuteCallback vad_mute_cb_;
    TtsPurgeCallback tts_purge_cb_;
    EarconCallback earcon_cb_;
    HapticCallback haptic_cb_;

    void executeHardInterrupt(const KalmanTrack& hazard, uint64_t trigger_start_ns);
    float computeIou(const BoundingBox& a, const BoundingBox& b) const;
};

} // namespace orbisnav

#endif // PERCEPTION_PREEMPTION_H
