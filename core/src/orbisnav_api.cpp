#include "../include/orbisnav_api.h"
#include "../include/orbisnav_engine.h"
#include <cstring>
#include <vector>

using namespace orbisnav;

static OrbisNavSpeechCallback s_speech_cb = nullptr;
static OrbisNavHapticCallback s_haptic_cb = nullptr;
static OrbisNavEarconCallback s_earcon_cb = nullptr;

bool orbisnav_init(void) {
    OrbisNavEngine& engine = OrbisNavEngine::instance();

    engine.registerSpeechCallback([](const std::string& text, AudioPriority priority) {
        if (s_speech_cb) {
            s_speech_cb(text.c_str(), static_cast<uint8_t>(priority));
        }
    });

    engine.registerHapticCallback([](const HapticPattern& pattern, float azimuth_deg) {
        if (s_haptic_cb) {
            s_haptic_cb(pattern.pulse_count, pattern.pulse_duration_ms, pattern.pause_duration_ms, pattern.intensity, azimuth_deg);
        }
    });

    engine.registerEarconCallback([](const DirectionalEarcon& earcon) {
        if (s_earcon_cb) {
            s_earcon_cb(earcon.azimuth_deg, earcon.elevation_deg, earcon.intensity, earcon.frequency_hz, earcon.duration_ms);
        }
    });

    return engine.coldBoot();
}

void orbisnav_shutdown(void) {
    OrbisNavEngine::instance().shutdown();
}

void orbisnav_register_speech_callback(OrbisNavSpeechCallback cb) {
    s_speech_cb = cb;
}

void orbisnav_register_haptic_callback(OrbisNavHapticCallback cb) {
    s_haptic_cb = cb;
}

void orbisnav_register_earcon_callback(OrbisNavEarconCallback cb) {
    s_earcon_cb = cb;
}

void orbisnav_ingest_frame(const uint8_t* y_data, size_t y_size, uint32_t width, uint32_t height, uint64_t timestamp_ns) {
    OrbisNavEngine::instance().ingestYuv420Frame(y_data, y_size, width, height, timestamp_ns);
}

void orbisnav_ingest_imu(float pitch_deg, float roll_deg, float yaw_deg, uint64_t timestamp_ns) {
    OrbisNavEngine::instance().ingestImuSample(pitch_deg, roll_deg, yaw_deg, timestamp_ns);
}

void orbisnav_set_soc_temperature(float temp_celsius) {
    OrbisNavEngine::instance().setSoCTemperature(temp_celsius);
}

void orbisnav_ingest_detection(float x_min, float y_min, float x_max, float y_max, float confidence, uint16_t class_id, uint64_t timestamp_ns) {
    BoundingBox bbox;
    bbox.x_min = x_min;
    bbox.y_min = y_min;
    bbox.x_max = x_max;
    bbox.y_max = y_max;
    bbox.confidence = confidence;
    bbox.class_id = static_cast<ObstacleClass>(class_id);

    std::vector<BoundingBox> dets{bbox};
    OrbisNavEngine::instance().ingestVisionDetections(dets, timestamp_ns);
}

void orbisnav_add_map_node(uint32_t id, const char* name, float x, float y, const char* plaque_label) {
    std::string node_name = name ? name : "";
    std::string plaque = plaque_label ? plaque_label : "";
    OrbisNavEngine::instance().configureMapNode(id, node_name, x, y, plaque);
}

void orbisnav_add_map_edge(uint32_t from_id, uint32_t to_id, float distance) {
    OrbisNavEngine::instance().configureMapEdge(from_id, to_id, distance);
}

int32_t orbisnav_compute_path(uint32_t start_id, uint32_t goal_id, uint32_t* out_path, size_t max_len) {
    auto path = OrbisNavEngine::instance().planPath(start_id, goal_id);
    size_t count = std::min(path.size(), max_len);
    for (size_t i = 0; i < count; ++i) {
        out_path[i] = path[i];
    }
    return static_cast<int32_t>(count);
}

uint8_t orbisnav_get_clock_direction(uint32_t target_node_id) {
    ClockDirection dir = OrbisNavEngine::instance().getNextWaypointClockDirection(target_node_id);
    return static_cast<uint8_t>(dir);
}

void orbisnav_ingest_pdr_step(float step_length, float heading_rad) {
    OrbisNavEngine::instance().ingestPdrStep(step_length, heading_rad);
}

bool orbisnav_ingest_ocr_reading(const char* detected_text) {
    if (!detected_text) return false;
    return OrbisNavEngine::instance().ingestOcrPlaqueReading(detected_text);
}

void orbisnav_set_conversation(const char* query, const char* response) {
    std::string q = query ? query : "";
    std::string r = response ? response : "";
    OrbisNavEngine::instance().startConversationalDialogue(q, r);
}

void orbisnav_update_conversation_lifecycle(uint64_t timestamp_ns) {
    OrbisNavEngine::instance().updateConversationalLifecycle(timestamp_ns);
}

void orbisnav_set_battery_percent(uint32_t battery_percent) {
    OrbisNavEngine::instance().setBatteryLevel(battery_percent);
}

uint64_t orbisnav_get_boot_duration_ms(void) {
    return OrbisNavEngine::instance().getEngineStats().cold_boot_duration_ms;
}

size_t orbisnav_get_memory_used_bytes(void) {
    return OrbisNavEngine::instance().getEngineStats().total_memory_allocated_bytes;
}

bool orbisnav_is_within_memory_budget(void) {
    return OrbisNavEngine::instance().getEngineStats().is_memory_compliant;
}

uint32_t orbisnav_get_target_fps(void) {
    return OrbisNavEngine::instance().getEngineStats().current_fps;
}

uint8_t orbisnav_get_thermal_band(void) {
    return static_cast<uint8_t>(OrbisNavEngine::instance().getEngineStats().current_thermal_band);
}

bool orbisnav_is_hazard_active(void) {
    return OrbisNavEngine::instance().getPerceptionEngine().isCriticalHazardActive();
}

bool orbisnav_is_conversation_suspended(void) {
    return OrbisNavEngine::instance().getEngineStats().is_conversation_suspended;
}
