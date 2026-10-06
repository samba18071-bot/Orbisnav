#ifndef ORBISNAV_TYPES_H
#define ORBISNAV_TYPES_H

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <array>
#include <chrono>

namespace orbisnav {

// Static Memory Budget (Total <= 180 MB)
constexpr size_t TOTAL_MEMORY_BUDGET_BYTES = 180 * 1024 * 1024; // 180 MB
constexpr size_t FRAME_BUFFER_POOL_BYTES   = 48 * 1024 * 1024;  // 48 MB for YUV420 frame ring buffer
constexpr size_t INFERENCE_SCRATCHPAD_BYTES = 100 * 1024 * 1024; // 100 MB for INT8 models & tensors
constexpr size_t AUDIO_SAMPLE_POOL_BYTES    = 16 * 1024 * 1024;  // 16 MB for spatial earcon/TTS cache
constexpr size_t SENSOR_QUEUE_POOL_BYTES    = 16 * 1024 * 1024;  // 16 MB for IMU/PDR/Nav queues

// Vector 3D & 2D representation
struct Vector3 {
    float x{0.0f};
    float y{0.0f};
    float z{0.0f};
};

struct Vector2 {
    float x{0.0f};
    float y{0.0f};
};

// Camera frame description (YUV420)
struct Yuv420Frame {
    uint32_t width{0};
    uint32_t height{0};
    uint64_t timestamp_ns{0};
    uint8_t* y_plane{nullptr};
    uint8_t* u_plane{nullptr};
    uint8_t* v_plane{nullptr};
    size_t y_stride{0};
    size_t uv_stride{0};
};

// IMU Sensor State
struct ImuOrientation {
    float pitch_deg{0.0f};  // Rotation around lateral axis (>30 deg below horizon triggers warning)
    float roll_deg{0.0f};
    float yaw_deg{0.0f};
    uint64_t timestamp_ns{0};
};

// Dynamic Thermal Throttling Bands
enum class ThermalBand : uint8_t {
    Nominal_Under40C  = 0, // 30 FPS Nominal Vision
    Warm_40C_to_43C   = 1, // 20 FPS (Skip 1 of 3 frames)
    Hot_43C_to_46C    = 2, // 15 FPS (Hazard detection prioritized over OCR)
    Critical_Over46C  = 3  // 10 FPS (Haptic-only spatial pulses)
};

// Obstacle Classes for YOLOv8-Nano
enum class ObstacleClass : uint16_t {
    Unknown = 0,
    Stairs = 1,
    Vehicle = 2,
    Door = 3,
    Seating = 4,
    Pedestrian = 5,
    DropOff = 6,
    Pillar = 7,
    Tree = 8
};

// Bounding box in normalized coordinates [0, 1]
struct BoundingBox {
    float x_min{0.0f};
    float y_min{0.0f};
    float x_max{0.0f};
    float y_max{0.0f};
    float confidence{0.0f};
    ObstacleClass class_id{ObstacleClass::Unknown};
};

// Tracked Obstacle from ByteTrack Kalman Filter
struct TrackedObstacle {
    uint32_t track_id{0};
    ObstacleClass class_id{ObstacleClass::Unknown};
    BoundingBox bbox;
    Vector3 position;       // 3D position in meters relative to camera (x=right, y=up, z=forward)
    Vector3 velocity;       // Velocity in m/s
    float distance{0.0f};   // Distance in meters
    float ttc_seconds{0.0f};// Time-to-Collision (TTC)
    uint64_t last_seen_ns{0};
    bool is_critical_hazard{false}; // Distance < 1.5m or TTC < 1.5s
};

// Directional 3D Audio Cue Earcon
struct DirectionalEarcon {
    float azimuth_deg{0.0f};    // Clockwise azimuth (-180 to +180, 0 = forward)
    float elevation_deg{0.0f};
    float intensity{1.0f};
    uint32_t frequency_hz{880}; // Pitch of warning tone
    uint32_t duration_ms{200};
};

// Audio Prioritization Levels
enum class AudioPriority : uint8_t {
    Level0_HazardAlert = 0,   // Critical preemption (<30ms hard interrupt)
    Level1_NavigationCue = 1, // Immediate turn / direction cue
    Level2_Informational = 2, // OCR door numbers, landmarks
    Level3_Conversational = 3 // LLM voice response / user dialogue
};

// Clock-Face Direction
enum class ClockDirection : uint8_t {
    TwelveOClock = 12,
    OneOClock    = 1,
    TwoOClock    = 2,
    ThreeOClock  = 3,
    FourOClock   = 4,
    FiveOClock   = 5,
    SixOClock    = 6,
    SevenOClock  = 7,
    EightOClock  = 8,
    NineOClock   = 9,
    TenOClock    = 10,
    ElevenOClock = 11
};

// Navigation Graph Node
struct NavNode {
    uint32_t id{0};
    std::string name;
    Vector2 coordinate; // in meters (indoor local or UTM outdoor)
    bool is_indoor{true};
    std::string plaque_label; // e.g., "Room 204", "Exit B"
    uint32_t floor_level{1};
    std::string node_type{"corridor"}; // entrance, elevator, corridor, stairwell, door
};

// PDR State
struct PdrState {
    Vector2 current_pos{0.0f, 0.0f};
    float heading_rad{0.0f};
    uint32_t step_count{0};
    Vector2 accumulated_drift{0.0f, 0.0f}; // e_drift
};

// Conversational State for suspension & auto-resumption
struct ConversationContext {
    std::string user_query;
    std::string partial_llm_response;
    uint32_t response_cursor{0};
    uint64_t suspended_timestamp_ns{0};
    bool is_active{false};
};

// Haptic Pattern Definition
struct HapticPattern {
    uint32_t pulse_count{0};
    uint32_t pulse_duration_ms{0};
    uint32_t pause_duration_ms{0};
    float intensity{1.0f};
};

enum class HapticZone : uint8_t {
    Zone3_Silent = 3,          // > 3.0m: Silent (0 vibration)
    Zone2_LowImpact = 2,       // 1.5m - 3.0m: Single low-impact pulse every 1.5s
    Zone1_MediumImpact = 1,    // 1.0m - 1.5m: Double medium-impact pulse
    Zone0_ContinuousHeavy = 0, // < 1.0m: Continuous heavy high-frequency pulse
    LevelChange_Stairs = 4     // Stairs / Level-change <= 1.5m: Rhythmic triple-tap vibration
};

// Step 6.2: 4-Zone Haptic Pulse Encoding helper
inline HapticPattern encodeHapticPattern(float distance_meters, ObstacleClass obstacle_class = ObstacleClass::Unknown) {
    if (obstacle_class == ObstacleClass::Stairs && distance_meters <= 1.5f) {
        // Level-Change / Stairs (<= 1.5m): Rhythmic triple-tap vibration
        return HapticPattern{3, 45, 45, 1.0f};
    }
    if (distance_meters < 1.0f) {
        // Zone 0 (< 1.0m): Continuous heavy high-frequency pulse
        return HapticPattern{10, 80, 20, 1.0f};
    } else if (distance_meters <= 1.5f) {
        // Zone 1 (1.0m - 1.5m): Double medium-impact pulse
        return HapticPattern{2, 60, 40, 0.7f};
    } else if (distance_meters <= 3.0f) {
        // Zone 2 (1.5m - 3.0m): Single low-impact pulse every 1.5s
        return HapticPattern{1, 40, 0, 0.4f};
    } else {
        // Zone 3 (> 3.0m): Silent (0 vibration)
        return HapticPattern{0, 0, 0, 0.0f};
    }
}

} // namespace orbisnav

#endif // ORBISNAV_TYPES_H
