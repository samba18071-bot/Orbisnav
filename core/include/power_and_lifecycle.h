#ifndef POWER_AND_LIFECYCLE_H
#define POWER_AND_LIFECYCLE_H

#include "orbisnav_types.h"
#include <functional>
#include <cstdint>

namespace orbisnav {

enum class FeedbackMode : uint8_t {
    FullMultimodal = 0,     // 3D Audio + Haptics + Speech
    FourZoneHapticOnly = 1  // Low power / Critical thermal 4-Zone Haptic Pulses
};

class PowerAndLifecycleManager {
public:
    using LowBatteryCallback = std::function<void(uint32_t battery_percent)>;
    using ShutdownCallback = std::function<void()>;

    PowerAndLifecycleManager();
    ~PowerAndLifecycleManager();

    void registerLowBatteryCallback(LowBatteryCallback cb) { low_batt_cb_ = cb; }
    void registerShutdownCallback(ShutdownCallback cb) { shutdown_cb_ = cb; }

    // Phase 6.1: Battery Level Monitoring
    // Low Battery Override (<= 15%): Unload OCR/LLM, downclock camera to 10 FPS,
    // switch feedback to 4-Zone Haptic Pulses
    bool updateBatteryLevel(uint32_t battery_percentage);

    // Phase 6.2: Graceful Shutdown
    // Flush remaining C++ memory buffers, unregister platform streams, release native camera handles
    void executeGracefulShutdown();

    // Queries
    bool isLowPowerMode() const { return low_power_mode_; }
    uint32_t getBatteryPercent() const { return current_battery_percent_; }
    FeedbackMode getFeedbackMode() const { return feedback_mode_; }
    uint32_t getDownclockedFps() const { return downclocked_fps_; }
    bool isTerminated() const { return is_terminated_; }

private:
    uint32_t current_battery_percent_{100};
    bool low_power_mode_{false};
    FeedbackMode feedback_mode_{FeedbackMode::FullMultimodal};
    uint32_t downclocked_fps_{30};
    bool is_terminated_{false};

    LowBatteryCallback low_batt_cb_;
    ShutdownCallback shutdown_cb_;
};

} // namespace orbisnav

#endif // POWER_AND_LIFECYCLE_H
