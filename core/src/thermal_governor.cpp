#include "../include/thermal_governor.h"
#include <chrono>
#include <iostream>

namespace orbisnav {

ThermalGovernor::ThermalGovernor()
    : current_temp_c_(35.0f),
      current_pitch_deg_(0.0f),
      current_band_(ThermalBand::Nominal_Under40C),
      target_fps_(30),
      enable_ocr_(true),
      haptic_only_mode_(false),
      last_tilt_warning_ns_(0) {}

ThermalGovernor::~ThermalGovernor() = default;

bool ThermalGovernor::updateImuOrientation(const ImuOrientation& orientation) {
    current_pitch_deg_ = orientation.pitch_deg;

    // Spec: "If the device points >30 deg below horizon, issue a quiet haptic tick and prompt: 'Tilt phone up.'"
    // By convention, pitch below horizon is negative (or positive depending on coordinate system).
    // Here we check if angle below horizon > 30 degrees (i.e. pitch < -30.0f or pitch > 30.0f when defined as downward tilt).
    // Let's support both downward tilt > 30.0f or < -30.0f:
    bool is_pointing_down = (orientation.pitch_deg < -30.0f) || (orientation.pitch_deg > 30.0f && orientation.roll_deg < 45.0f && orientation.pitch_deg < 85.0f);

    if (orientation.pitch_deg < -30.0f) {
        is_pointing_down = true;
    }

    if (is_pointing_down) {
        uint64_t now_ns = orientation.timestamp_ns;
        if (now_ns == 0) {
            now_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
                         std::chrono::steady_clock::now().time_since_epoch()).count();
        }

        if (last_tilt_warning_ns_ == 0 || (now_ns - last_tilt_warning_ns_ >= TILT_WARN_DEBOUNCE_NS)) {
            last_tilt_warning_ns_ = now_ns;

            // Quiet haptic tick (single discrete 30ms soft pulse)
            HapticPattern quiet_tick{1, 30, 0, 0.4f};
            if (tilt_cb_) {
                tilt_cb_("Tilt phone up.", quiet_tick);
            }
            return true;
        }
    }
    return false;
}

ThermalBand ThermalGovernor::updateSoCTemperature(float temperature_celsius) {
    current_temp_c_ = temperature_celsius;
    ThermalBand previous_band = current_band_;

    // Specification:
    // T_SoC < 40C      => 30 FPS (Nominal Vision Processing)
    // 40C <= T_SoC < 43C => 20 FPS (Skip 1 of 3 frames)
    // 43C <= T_SoC < 46C => 15 FPS (Hazard detection prioritized over OCR)
    // T_SoC >= 46C     => 10 FPS (Fall back to haptic-only spatial pulses)
    if (temperature_celsius < 40.0f) {
        current_band_ = ThermalBand::Nominal_Under40C;
        target_fps_ = 30;
        enable_ocr_ = true;
        haptic_only_mode_ = false;
    } else if (temperature_celsius < 43.0f) {
        current_band_ = ThermalBand::Warm_40C_to_43C;
        target_fps_ = 20;
        enable_ocr_ = true;
        haptic_only_mode_ = false;
    } else if (temperature_celsius < 46.0f) {
        current_band_ = ThermalBand::Hot_43C_to_46C;
        target_fps_ = 15;
        enable_ocr_ = false; // Prioritize hazard detection over OCR
        haptic_only_mode_ = false;
    } else {
        current_band_ = ThermalBand::Critical_Over46C;
        target_fps_ = 10;
        enable_ocr_ = false;
        haptic_only_mode_ = true; // Fall back to haptic-only spatial pulses
    }

    if (previous_band != current_band_ && thermal_cb_) {
        thermal_cb_(previous_band, current_band_, target_fps_);
    }

    return current_band_;
}

bool ThermalGovernor::shouldProcessFrame(uint64_t frame_index) {
    switch (current_band_) {
        case ThermalBand::Nominal_Under40C:
            // 30 FPS: process every frame
            return true;
        case ThermalBand::Warm_40C_to_43C:
            // 20 FPS: skip 1 of 3 frames (process index % 3 != 2)
            return (frame_index % 3 != 2);
        case ThermalBand::Hot_43C_to_46C:
            // 15 FPS: process 1 of 2 frames (process index % 2 == 0)
            return (frame_index % 2 == 0);
        case ThermalBand::Critical_Over46C:
            // 10 FPS: process 1 of 3 frames (process index % 3 == 0)
            return (frame_index % 3 == 0);
        default:
            return true;
    }
}

} // namespace orbisnav
