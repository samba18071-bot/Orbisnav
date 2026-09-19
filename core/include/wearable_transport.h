#ifndef WEARABLE_TRANSPORT_H
#define WEARABLE_TRANSPORT_H

#include <cstdint>
#include <cstddef>
#include <string>
#include <chrono>
#include <atomic>
#include <functional>

namespace orbisnav {

enum class TransportMode : uint8_t {
    SmartphoneCamera = 0,
    WearableBluetoothSpp = 1,
    WearableWifiDirect = 2
};

struct WearableFrameHeader {
    uint32_t frame_index{0};
    uint32_t payload_size_bytes{0}; // Must be <= 180 KB for MJPEG
    uint8_t quality_percent{70};     // Target Q = 65-75%
    uint64_t timestamp_ns{0};
};

class WearableTransportEngine {
public:
    using SocketStateCallback = std::function<void(bool socket_active, const std::string& reason)>;

    WearableTransportEngine();
    ~WearableTransportEngine();

    void registerSocketStateCallback(SocketStateCallback cb) { socket_cb_ = cb; }

    // Step 1.2: Bluetooth SPP MJPEG frame ingestion (Q = 65-75%, <= 180 KB)
    bool ingestBluetoothMjpegFrame(const uint8_t* mjpeg_data, size_t size_bytes, uint8_t quality, uint64_t timestamp_ns);

    // Step 1.2: Wi-Fi Direct socket handoff for dense micro-tasks (OCR/VQA)
    bool requestWifiDirectHandoff(const std::string& task_type, uint64_t timestamp_ns = 0);
    void reportSocketActivity(uint64_t timestamp_ns = 0);
    void auditSocketInactivity(uint64_t current_timestamp_ns);

    // Queries
    TransportMode getActiveMode() const { return current_mode_; }
    bool isWifiDirectSocketActive() const { return wifi_direct_socket_active_; }
    size_t getLastFrameSizeBytes() const { return last_frame_size_bytes_; }
    uint8_t getLastQualityPercent() const { return last_quality_percent_; }
    uint64_t getInactivityElapsedSec(uint64_t current_timestamp_ns) const;

private:
    TransportMode current_mode_{TransportMode::SmartphoneCamera};
    std::atomic<bool> wifi_direct_socket_active_{false};
    uint64_t last_socket_activity_ns_{0};
    static constexpr uint64_t SOCKET_INACTIVITY_TIMEOUT_NS = 10000000000ULL; // 10 seconds

    size_t last_frame_size_bytes_{0};
    uint8_t last_quality_percent_{70};

    SocketStateCallback socket_cb_;
};

} // namespace orbisnav

#endif // WEARABLE_TRANSPORT_H
