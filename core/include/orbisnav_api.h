#ifndef ORBISNAV_API_H
#define ORBISNAV_API_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque engine handle
typedef struct OrbisNavEngineHandle OrbisNavEngineHandle;

// Callbacks
typedef void (*OrbisNavSpeechCallback)(const char* text, uint8_t priority);
typedef void (*OrbisNavHapticCallback)(uint32_t pulse_count, uint32_t pulse_ms, uint32_t pause_ms, float intensity, float azimuth_deg);
typedef void (*OrbisNavEarconCallback)(float azimuth_deg, float elevation_deg, float intensity, uint32_t freq_hz, uint32_t duration_ms);

// Lifecycle API
bool orbisnav_init(void);
void orbisnav_shutdown(void);

// Registration
void orbisnav_register_speech_callback(OrbisNavSpeechCallback cb);
void orbisnav_register_haptic_callback(OrbisNavHapticCallback cb);
void orbisnav_register_earcon_callback(OrbisNavEarconCallback cb);

// Sensor & Vision Ingestion
void orbisnav_ingest_frame(const uint8_t* y_data, size_t y_size, uint32_t width, uint32_t height, uint64_t timestamp_ns);
void orbisnav_ingest_imu(float pitch_deg, float roll_deg, float yaw_deg, uint64_t timestamp_ns);
void orbisnav_set_soc_temperature(float temp_celsius);

// Hazard & Bounding Box Ingestion
void orbisnav_ingest_detection(float x_min, float y_min, float x_max, float y_max, float confidence, uint16_t class_id, uint64_t timestamp_ns);

// Navigation & PDR
void orbisnav_add_map_node(uint32_t id, const char* name, float x, float y, const char* plaque_label);
void orbisnav_add_map_edge(uint32_t from_id, uint32_t to_id, float distance);
int32_t orbisnav_compute_path(uint32_t start_id, uint32_t goal_id, uint32_t* out_path, size_t max_len);
uint8_t orbisnav_get_clock_direction(uint32_t target_node_id);
void orbisnav_ingest_pdr_step(float step_length, float heading_rad);
bool orbisnav_ingest_ocr_reading(const char* detected_text);

// Conversational Suspension & Resume
void orbisnav_set_conversation(const char* query, const char* response);
void orbisnav_update_conversation_lifecycle(uint64_t timestamp_ns);

// Power Governance
void orbisnav_set_battery_percent(uint32_t battery_percent);

// Metrics & Diagnostics
uint64_t orbisnav_get_boot_duration_ms(void);
size_t orbisnav_get_memory_used_bytes(void);
bool orbisnav_is_within_memory_budget(void);
uint32_t orbisnav_get_target_fps(void);
uint8_t orbisnav_get_thermal_band(void);
bool orbisnav_is_hazard_active(void);
bool orbisnav_is_conversation_suspended(void);

#ifdef __cplusplus
}
#endif

#endif // ORBISNAV_API_H
