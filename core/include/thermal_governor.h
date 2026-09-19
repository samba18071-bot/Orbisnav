#ifndef THERMAL_GOVERNOR_H
#define THERMAL_GOVERNOR_H

#include "orbisnav_types.h"
#include <functional>
#include <cstdint>

namespace orbisnav {

class ThermalGovernor {
public:
    using TiltCallback = std::function<void(const std::string& prompt, const HapticPattern& haptic)>;
    using ThermalCallback = std::function<void(ThermalBand old_band, ThermalBand new_band, uint32_t target_fps)>;

    ThermalGovernor();
    ~ThermalGovernor();

    void registerTiltCallback(TiltCallback cb) { tilt_cb_ = cb; }
    void registerThermalCallback(ThermalCallback cb) { thermal_cb_ = cb; }

    // Phase 2.2: IMU Orientation Audit
    // Phone pitch > 30 deg below horizon triggers quiet haptic tick & prompt "Tilt phone up."
    bool updateImuOrientation(const ImuOrientation& orientation);

    // Phase 2.3: Dynamic Thermal Throttling
    // Evaluates current SoC temperature and sets FPS / processing policy
    ThermalBand updateSoCTemperature(float temperature_celsius);

    // Frame gating query: should current frame be processed according to thermal throttling?
    bool shouldProcessFrame(uint64_t frame_index);

    // Policy queries
    uint32_t getTargetFps() const { return target_fps_; }
    ThermalBand getCurrentBand() const { return current_band_; }
    bool isOcrEnabled() const { return enable_ocr_; }
    bool isHapticOnlyMode() const { return haptic_only_mode_; }

    float getCurrentPitch() const { return current_pitch_deg_; }
    float getCurrentTemperature() const { return current_temp_c_; }

private:
    float current_temp_c_{35.0f};
    float current_pitch_deg_{0.0f};
    ThermalBand current_band_{ThermalBand::Nominal_Under40C};
    uint32_t target_fps_{30};
    bool enable_ocr_{true};
    bool haptic_only_mode_{false};

    uint64_t last_tilt_warning_ns_{0};
    static constexpr uint64_t TILT_WARN_DEBOUNCE_NS = 2000000000ULL; // 2 sec debounce on tilt prompts

    TiltCallback tilt_cb_;
    ThermalCallback thermal_cb_;
};

} // namespace orbisnav

#endif // THERMAL_GOVERNOR_H
