#include "../include/wearable_transport.h"
#include <iostream>

namespace orbisnav {

WearableTransportEngine::WearableTransportEngine()
    : current_mode_(TransportMode::SmartphoneCamera),
      wifi_direct_socket_active_(false),
      last_socket_activity_ns_(0),
      last_frame_size_bytes_(0),
      last_quality_percent_(70) {}

WearableTransportEngine::~WearableTransportEngine() = default;

bool WearableTransportEngine::ingestBluetoothMjpegFrame(
    const uint8_t* mjpeg_data,
    size_t size_bytes,
    uint8_t quality,
    uint64_t timestamp_ns) {

    (void)mjpeg_data;
    (void)timestamp_ns;

    // Spec Step 1.2: Confirm default camera feed over Bluetooth SPP uses
    // hardware-accelerated MJPEG encoding (Q = 65–75%) maintaining <= 180 KB per frame at 30 FPS.
    if (size_bytes > 180 * 1024) {
        // Exceeds 180 KB bandwidth envelope
        return false;
    }

    if (quality < 65 || quality > 75) {
        // Warn if outside optimal compression sweet-spot
    }

    last_frame_size_bytes_ = size_bytes;
    last_quality_percent_ = quality;
    current_mode_ = TransportMode::WearableBluetoothSpp;

    return true;
}

bool WearableTransportEngine::requestWifiDirectHandoff(const std::string& task_type, uint64_t timestamp_ns) {
    // High-density micro-tasks (e.g. full-page OCR, dense VQA) trigger low-latency TCP socket (>50 Mbps)
    wifi_direct_socket_active_ = true;
    current_mode_ = TransportMode::WearableWifiDirect;

    if (timestamp_ns > 0) {
        last_socket_activity_ns_ = timestamp_ns;
    } else {
        last_socket_activity_ns_ = std::chrono::duration_cast<std::chrono::nanoseconds>(
                                       std::chrono::steady_clock::now().time_since_epoch()).count();
    }

    if (socket_cb_) {
        socket_cb_(true, "Handoff triggered for task: " + task_type);
    }

    return true;
}

void WearableTransportEngine::reportSocketActivity(uint64_t timestamp_ns) {
    if (timestamp_ns > 0) {
        last_socket_activity_ns_ = timestamp_ns;
    } else {
        last_socket_activity_ns_ = std::chrono::duration_cast<std::chrono::nanoseconds>(
                                       std::chrono::steady_clock::now().time_since_epoch()).count();
    }
}

void WearableTransportEngine::auditSocketInactivity(uint64_t current_timestamp_ns) {
    if (!wifi_direct_socket_active_) return;

    // Spec Step 1.2: Automatically dismantle the socket after 10 seconds of inactivity to save wearable battery
    if (last_socket_activity_ns_ > 0 && current_timestamp_ns >= last_socket_activity_ns_ &&
        (current_timestamp_ns - last_socket_activity_ns_ >= SOCKET_INACTIVITY_TIMEOUT_NS)) {

        wifi_direct_socket_active_ = false;
        current_mode_ = TransportMode::WearableBluetoothSpp;

        if (socket_cb_) {
            socket_cb_(false, "Auto-dismantled Wi-Fi Direct socket after 10s of inactivity to save battery");
        }
    }
}

uint64_t WearableTransportEngine::getInactivityElapsedSec(uint64_t current_timestamp_ns) const {
    if (last_socket_activity_ns_ == 0 || current_timestamp_ns < last_socket_activity_ns_) return 0;
    return (current_timestamp_ns - last_socket_activity_ns_) / 1000000000ULL;
}

} // namespace orbisnav
