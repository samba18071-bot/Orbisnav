#include "../include/power_and_lifecycle.h"
#include "../include/zero_heap_allocator.h"
#include <iostream>

namespace orbisnav {

PowerAndLifecycleManager::PowerAndLifecycleManager()
    : current_battery_percent_(100),
      low_power_mode_(false),
      feedback_mode_(FeedbackMode::FullMultimodal),
      downclocked_fps_(30),
      is_terminated_(false) {}

PowerAndLifecycleManager::~PowerAndLifecycleManager() {
    if (!is_terminated_) {
        executeGracefulShutdown();
    }
}

bool PowerAndLifecycleManager::updateBatteryLevel(uint32_t battery_percentage) {
    current_battery_percent_ = battery_percentage;

    // Spec: Low Battery Override (<= 15%)
    if (battery_percentage <= 15) {
        if (!low_power_mode_) {
            low_power_mode_ = true;
            downclocked_fps_ = 10; // Downclock camera stream to 10 FPS
            feedback_mode_ = FeedbackMode::FourZoneHapticOnly; // 4-Zone Haptic Pulses

            if (low_batt_cb_) {
                low_batt_cb_(battery_percentage);
            }
            return true;
        }
    } else {
        if (low_power_mode_) {
            low_power_mode_ = false;
            downclocked_fps_ = 30;
            feedback_mode_ = FeedbackMode::FullMultimodal;
        }
    }

    return false;
}

void PowerAndLifecycleManager::executeGracefulShutdown() {
    if (is_terminated_) return;

    // Spec Phase 6.2: Graceful Shutdown:
    // On exit, flush remaining C++ memory buffers, unregister platform streams,
    // and release native camera handles.
    ZeroHeapAllocator::instance().flushAndRelease();

    if (shutdown_cb_) {
        shutdown_cb_();
    }

    is_terminated_ = true;
}

} // namespace orbisnav
