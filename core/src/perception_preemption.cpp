#include "../include/perception_preemption.h"
#include <cmath>
#include <algorithm>
#include <iostream>

namespace orbisnav {

PerceptionPreemptionEngine::PerceptionPreemptionEngine()
    : critical_hazard_active_(false),
      last_hazard_clear_ns_(0),
      preemption_count_(0),
      last_preemption_latency_ms_(0.0f) {}

PerceptionPreemptionEngine::~PerceptionPreemptionEngine() = default;

float PerceptionPreemptionEngine::computeIou(const BoundingBox& a, const BoundingBox& b) const {
    float x1 = std::max(a.x_min, b.x_min);
    float y1 = std::max(a.y_min, b.y_min);
    float x2 = std::min(a.x_max, b.x_max);
    float y2 = std::min(a.y_max, b.y_max);

    float width = std::max(0.0f, x2 - x1);
    float height = std::max(0.0f, y2 - y1);
    float inter_area = width * height;

    float area_a = (a.x_max - a.x_min) * (a.y_max - a.y_min);
    float area_b = (b.x_max - b.x_min) * (b.y_max - b.y_min);
    float union_area = area_a + area_b - inter_area;

    if (union_area <= 0.0f) return 0.0f;
    return inter_area / union_area;
}

bool PerceptionPreemptionEngine::shouldDebounce(const BoundingBox& bbox, uint64_t timestamp_ns) {
    // Purge records older than 800ms from the sliding window
    while (!debounce_window_.empty()) {
        if (timestamp_ns - debounce_window_.front().timestamp_ns > DEBOUNCE_WINDOW_NS) {
            debounce_window_.pop_front();
        } else {
            break;
        }
    }

    // Check overlap with active records in the 800ms window
    for (const auto& rec : debounce_window_) {
        if (rec.class_id == bbox.class_id) {
            float iou = computeIou(rec.bbox, bbox);
            if (iou >= 0.45f) {
                // Duplicate detection within 800ms sliding window -> debounce
                return true;
            }
        }
    }

    // Add to sliding window
    debounce_window_.push_back({timestamp_ns, bbox, bbox.class_id});
    return false;
}

std::vector<TrackedObstacle> PerceptionPreemptionEngine::processDetections(
    const std::vector<BoundingBox>& detections,
    uint64_t frame_timestamp_ns) {

    std::vector<TrackedObstacle> tracked_results;
    bool found_hazard_this_frame = false;

    // 1. Predict track states (ByteTrack Kalman update)
    for (auto& track : tracks_) {
        track.time_since_update++;
        // State extrapolation
        float dt = 0.033f; // nominal 30fps = ~33ms
        track.position.x += track.velocity.x * dt;
        track.position.y += track.velocity.y * dt;
        track.position.z += track.velocity.z * dt;
        track.distance = std::sqrt(track.position.x * track.position.x +
                                   track.position.y * track.position.y +
                                   track.position.z * track.position.z);
    }

    // 2. Association & Update
    std::vector<bool> matched_dets(detections.size(), false);

    for (auto& track : tracks_) {
        int best_match_idx = -1;
        float best_iou = 0.3f; // matching threshold

        for (size_t i = 0; i < detections.size(); ++i) {
            if (matched_dets[i]) continue;
            float iou = computeIou(track.bbox, detections[i]);
            if (iou > best_iou) {
                best_iou = iou;
                best_match_idx = static_cast<int>(i);
            }
        }

        if (best_match_idx >= 0) {
            matched_dets[best_match_idx] = true;
            const auto& det = detections[best_match_idx];

            // Estimate 3D position from bounding box geometry
            // Box center x in [-1, 1], height inversely proportional to distance z
            float center_x = ((det.x_min + det.x_max) * 0.5f - 0.5f) * 2.0f; // -1 (left) to +1 (right)
            float box_h = std::max(0.01f, det.y_max - det.y_min);
            
            // Empirical focal depth: standard human / vehicle height mapping
            float est_z = std::max(0.3f, 1.2f / box_h);
            float est_x = center_x * (est_z * 0.6f);
            float est_y = 0.0f;

            // Compute velocity via Kalman filter blend
            float dt = 0.033f;
            if (track.last_updated_ns > 0) {
                float real_dt = static_cast<float>(frame_timestamp_ns - track.last_updated_ns) / 1e9f;
                if (real_dt > 0.005f && real_dt < 0.5f) dt = real_dt;
            }

            Vector3 new_vel;
            new_vel.x = (est_x - track.position.x) / dt;
            new_vel.y = (est_y - track.position.y) / dt;
            new_vel.z = (est_z - track.position.z) / dt;

            // Low-pass filter velocity
            track.velocity.x = 0.7f * track.velocity.x + 0.3f * new_vel.x;
            track.velocity.y = 0.7f * track.velocity.y + 0.3f * new_vel.y;
            track.velocity.z = 0.7f * track.velocity.z + 0.3f * new_vel.z;

            track.position.x = est_x;
            track.position.y = est_y;
            track.position.z = est_z;
            track.bbox = det;
            track.class_id = det.class_id;
            track.distance = std::sqrt(est_x * est_x + est_y * est_y + est_z * est_z);
            track.last_updated_ns = frame_timestamp_ns;
            track.hits++;
            track.time_since_update = 0;

            // Calculate Time-To-Collision (TTC)
            // Closing velocity toward camera: -velocity.z (since camera looks down +z)
            float closing_speed = -track.velocity.z;
            // Also account for nominal walking speed of user (~1.2 m/s forward)
            float total_closing_speed = closing_speed + 1.2f;

            if (total_closing_speed > 0.1f) {
                track.ttc_seconds = track.distance / total_closing_speed;
            } else {
                track.ttc_seconds = 999.0f;
            }
        }
    }

    // 3. Initiate new tracks for unmatched detections
    for (size_t i = 0; i < detections.size(); ++i) {
        if (!matched_dets[i]) {
            const auto& det = detections[i];
            KalmanTrack new_track;
            new_track.track_id = next_track_id_++;
            new_track.class_id = det.class_id;
            new_track.bbox = det;

            float center_x = ((det.x_min + det.x_max) * 0.5f - 0.5f) * 2.0f;
            float box_h = std::max(0.01f, det.y_max - det.y_min);
            float est_z = std::max(0.3f, 1.2f / box_h);
            float est_x = center_x * (est_z * 0.6f);

            new_track.position = {est_x, 0.0f, est_z};
            new_track.velocity = {0.0f, 0.0f, 0.0f};
            new_track.distance = std::sqrt(est_x * est_x + est_z * est_z);
            new_track.ttc_seconds = new_track.distance / 1.2f; // using walking speed
            new_track.last_updated_ns = frame_timestamp_ns;
            new_track.hits = 1;
            new_track.time_since_update = 0;

            tracks_.push_back(new_track);
        }
    }

    // 4. Remove stale tracks
    tracks_.erase(
        std::remove_if(tracks_.begin(), tracks_.end(), [](const KalmanTrack& t) {
            return t.time_since_update > 10;
        }),
        tracks_.end()
    );

    // 5. Evaluate Critical Hazard Condition & Preemption
    // Specification: Critical Hazard Preemption (<1.5m or TTC < 1.5s)
    for (const auto& track : tracks_) {
        // Only evaluate active hazard for objects actively visible in the current frame
        if (track.time_since_update > 0) continue;

        bool is_critical = (track.distance < 1.5f || track.ttc_seconds < 1.5f);

        TrackedObstacle result;
        result.track_id = track.track_id;
        result.class_id = track.class_id;
        result.bbox = track.bbox;
        result.position = track.position;
        result.velocity = track.velocity;
        result.distance = track.distance;
        result.ttc_seconds = track.ttc_seconds;
        result.last_seen_ns = track.last_updated_ns;
        result.is_critical_hazard = is_critical;
        tracked_results.push_back(result);

        if (is_critical) {
            found_hazard_this_frame = true;

            // Debounce check to avoid alert storms
            bool debounced = shouldDebounce(track.bbox, frame_timestamp_ns);
            if (!debounced) {
                // Execute Hard Interrupt (<30ms)
                auto trigger_start = std::chrono::steady_clock::now();
                executeHardInterrupt(track, frame_timestamp_ns);
                auto trigger_end = std::chrono::steady_clock::now();
                last_preemption_latency_ms_ = std::chrono::duration<float, std::milli>(trigger_end - trigger_start).count();
            }
        }
    }

    if (found_hazard_this_frame) {
        critical_hazard_active_ = true;
    } else {
        if (critical_hazard_active_) {
            last_hazard_clear_ns_ = frame_timestamp_ns;
        }
        critical_hazard_active_ = false;
    }

    return tracked_results;
}

void PerceptionPreemptionEngine::executeHardInterrupt(const KalmanTrack& hazard, uint64_t trigger_start_ns) {
    (void)trigger_start_ns;
    preemption_count_++;

    // 1. Mute active microphone (VAD) instantly
    if (vad_mute_cb_) {
        vad_mute_cb_(true);
    }

    // 2. Purge active speech buffers via stopTTS()
    if (tts_purge_cb_) {
        tts_purge_cb_();
    }

    // 3. Dispatch directional 3D earcon tone and haptic vibration pattern
    // Azimuth: angle in degrees relative to camera forward (z-axis)
    // 0 deg = straight ahead (12 o'clock), +90 deg = right (3 o'clock), -90 deg = left (9 o'clock)
    float azimuth_rad = std::atan2(hazard.position.x, std::max(0.01f, hazard.position.z));
    float azimuth_deg = azimuth_rad * (180.0f / 3.1415926535f);

    DirectionalEarcon earcon;
    earcon.azimuth_deg = azimuth_deg;
    earcon.elevation_deg = 0.0f;
    earcon.intensity = 1.0f;
    earcon.frequency_hz = 950; // high urgency tone
    earcon.duration_ms = 150;

    if (earcon_cb_) {
        earcon_cb_(earcon);
    }

    // Urgent rapid haptic pulses
    HapticPattern urgent_haptic{3, 60, 40, 1.0f};
    if (haptic_cb_) {
        haptic_cb_(urgent_haptic, azimuth_deg);
    }
}

} // namespace orbisnav
