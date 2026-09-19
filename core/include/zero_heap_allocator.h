#ifndef ZERO_HEAP_ALLOCATOR_H
#define ZERO_HEAP_ALLOCATOR_H

#include "orbisnav_types.h"
#include <cstdint>
#include <cstddef>
#include <atomic>
#include <array>
#include <cstring>
#include <mutex>

namespace orbisnav {

class ZeroHeapAllocator {
public:
    static ZeroHeapAllocator& instance();

    // Cold boot initialization: returns true if initialized in <500ms within <= 180MB
    bool initialize();

    // Check footprint
    size_t getTotalAllocatedBytes() const;
    bool isWithinBudget() const; // asserts <= 180MB

    // Ring buffer slot for YUV420 frames
    struct FrameSlot {
        uint8_t* buffer{nullptr};
        size_t capacity{0};
        size_t size{0};
        uint64_t timestamp_ns{0};
        uint32_t width{0};
        uint32_t height{0};
        bool is_valid{false};
    };

    // Frame ring buffer interface (O(1), zero allocation)
    FrameSlot* acquireWriteFrameSlot();
    void commitWriteFrameSlot();
    const FrameSlot* acquireReadFrameSlot();
    void releaseReadFrameSlot();

    // Inference scratchpad memory access
    uint8_t* getInferenceScratchpad(size_t required_bytes);
    void resetInferenceScratchpad();

    // Audio sample buffer access
    uint8_t* getAudioBuffer(size_t required_bytes);
    void resetAudioBuffer();

    // Sensor sample ring buffer
    bool pushImuSample(const ImuOrientation& imu);
    bool popLatestImuSample(ImuOrientation& out_imu);

    // Teardown / memory flush
    void flushAndRelease();

private:
    ZeroHeapAllocator();
    ~ZeroHeapAllocator();
    ZeroHeapAllocator(const ZeroHeapAllocator&) = delete;
    ZeroHeapAllocator& operator=(const ZeroHeapAllocator&) = delete;

    // Frame pool configuration (e.g. 16 frames of 1920x1080 YUV420 ~ 3MB each -> ~48MB)
    static constexpr size_t NUM_FRAME_SLOTS = 16;
    static constexpr size_t MAX_FRAME_SIZE_BYTES = 3 * 1024 * 1024; // 3MB per slot

    // Static memory buffers
    uint8_t* raw_pool_memory_{nullptr};
    size_t total_pool_size_{TOTAL_MEMORY_BUDGET_BYTES};

    // Memory partitions
    uint8_t* frame_pool_{nullptr};
    uint8_t* inference_scratchpad_{nullptr};
    uint8_t* audio_pool_{nullptr};
    uint8_t* sensor_pool_{nullptr};

    std::array<FrameSlot, NUM_FRAME_SLOTS> frame_slots_;
    std::atomic<size_t> frame_write_idx_{0};
    std::atomic<size_t> frame_read_idx_{0};

    std::atomic<size_t> scratchpad_offset_{0};
    std::atomic<size_t> audio_offset_{0};

    // IMU Ring buffer
    static constexpr size_t IMU_RING_SIZE = 128;
    std::array<ImuOrientation, IMU_RING_SIZE> imu_ring_{};
    std::atomic<size_t> imu_head_{0};
    std::atomic<size_t> imu_tail_{0};

    bool initialized_{false};
    mutable std::mutex imu_mutex_;
};

} // namespace orbisnav

#endif // ZERO_HEAP_ALLOCATOR_H
