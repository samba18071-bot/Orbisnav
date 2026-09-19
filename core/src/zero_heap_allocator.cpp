#include "../include/zero_heap_allocator.h"
#include <chrono>
#include <iostream>
#include <cassert>

namespace orbisnav {

// Statically allocated global pool buffer in bss/data segment (or memory mapped)
// strictly conforming to <= 180MB footprint requirement
alignas(64) static uint8_t s_static_heap_pool[TOTAL_MEMORY_BUDGET_BYTES];

ZeroHeapAllocator& ZeroHeapAllocator::instance() {
    static ZeroHeapAllocator s_instance;
    return s_instance;
}

ZeroHeapAllocator::ZeroHeapAllocator() {
    raw_pool_memory_ = s_static_heap_pool;
    total_pool_size_ = sizeof(s_static_heap_pool);
}

ZeroHeapAllocator::~ZeroHeapAllocator() {
    flushAndRelease();
}

bool ZeroHeapAllocator::initialize() {
    auto start_time = std::chrono::steady_clock::now();

    // Verify budget at compile & runtime
    static_assert(sizeof(s_static_heap_pool) <= TOTAL_MEMORY_BUDGET_BYTES, 
                  "Pool size exceeds 180MB total memory budget!");

    // Zero out memory without allocating dynamically
    std::memset(raw_pool_memory_, 0, total_pool_size_);

    // Set up partitions
    uint8_t* ptr = raw_pool_memory_;

    frame_pool_ = ptr;
    ptr += FRAME_BUFFER_POOL_BYTES;

    inference_scratchpad_ = ptr;
    ptr += INFERENCE_SCRATCHPAD_BYTES;

    audio_pool_ = ptr;
    ptr += AUDIO_SAMPLE_POOL_BYTES;

    sensor_pool_ = ptr;
    ptr += SENSOR_QUEUE_POOL_BYTES;

    assert((ptr - raw_pool_memory_) <= static_cast<std::ptrdiff_t>(total_pool_size_));

    // Initialize Frame Ring Buffer Slots
    uint8_t* frame_ptr = frame_pool_;
    for (size_t i = 0; i < NUM_FRAME_SLOTS; ++i) {
        frame_slots_[i].buffer = frame_ptr;
        frame_slots_[i].capacity = MAX_FRAME_SIZE_BYTES;
        frame_slots_[i].size = 0;
        frame_slots_[i].timestamp_ns = 0;
        frame_slots_[i].width = 0;
        frame_slots_[i].height = 0;
        frame_slots_[i].is_valid = false;
        frame_ptr += MAX_FRAME_SIZE_BYTES;
    }

    frame_write_idx_.store(0, std::memory_order_relaxed);
    frame_read_idx_.store(0, std::memory_order_relaxed);
    scratchpad_offset_.store(0, std::memory_order_relaxed);
    audio_offset_.store(0, std::memory_order_relaxed);
    imu_head_.store(0, std::memory_order_relaxed);
    imu_tail_.store(0, std::memory_order_relaxed);

    initialized_ = true;

    auto end_time = std::chrono::steady_clock::now();
    auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

    // Spec check: Must initialize in <500ms
    return (elapsed_ms < 500);
}

size_t ZeroHeapAllocator::getTotalAllocatedBytes() const {
    return total_pool_size_;
}

bool ZeroHeapAllocator::isWithinBudget() const {
    return total_pool_size_ <= TOTAL_MEMORY_BUDGET_BYTES;
}

ZeroHeapAllocator::FrameSlot* ZeroHeapAllocator::acquireWriteFrameSlot() {
    if (!initialized_) return nullptr;
    size_t write_idx = frame_write_idx_.load(std::memory_order_relaxed);
    FrameSlot* slot = &frame_slots_[write_idx % NUM_FRAME_SLOTS];
    return slot;
}

void ZeroHeapAllocator::commitWriteFrameSlot() {
    if (!initialized_) return;
    size_t write_idx = frame_write_idx_.load(std::memory_order_relaxed);
    frame_slots_[write_idx % NUM_FRAME_SLOTS].is_valid = true;
    frame_write_idx_.fetch_add(1, std::memory_order_release);
}

const ZeroHeapAllocator::FrameSlot* ZeroHeapAllocator::acquireReadFrameSlot() {
    if (!initialized_) return nullptr;
    size_t read_idx = frame_read_idx_.load(std::memory_order_acquire);
    size_t write_idx = frame_write_idx_.load(std::memory_order_acquire);

    if (read_idx >= write_idx) {
        return nullptr; // No unread frames
    }

    const FrameSlot* slot = &frame_slots_[read_idx % NUM_FRAME_SLOTS];
    if (!slot->is_valid) {
        return nullptr;
    }
    return slot;
}

void ZeroHeapAllocator::releaseReadFrameSlot() {
    if (!initialized_) return;
    frame_read_idx_.fetch_add(1, std::memory_order_release);
}

uint8_t* ZeroHeapAllocator::getInferenceScratchpad(size_t required_bytes) {
    if (!initialized_) return nullptr;
    size_t current_offset = scratchpad_offset_.load(std::memory_order_relaxed);
    if (current_offset + required_bytes > INFERENCE_SCRATCHPAD_BYTES) {
        // Exceeds scratchpad buffer partition
        return nullptr;
    }
    uint8_t* result = inference_scratchpad_ + current_offset;
    scratchpad_offset_.fetch_add(required_bytes, std::memory_order_relaxed);
    return result;
}

void ZeroHeapAllocator::resetInferenceScratchpad() {
    scratchpad_offset_.store(0, std::memory_order_relaxed);
}

uint8_t* ZeroHeapAllocator::getAudioBuffer(size_t required_bytes) {
    if (!initialized_) return nullptr;
    size_t current_offset = audio_offset_.load(std::memory_order_relaxed);
    if (current_offset + required_bytes > AUDIO_SAMPLE_POOL_BYTES) {
        return nullptr;
    }
    uint8_t* result = audio_pool_ + current_offset;
    audio_offset_.fetch_add(required_bytes, std::memory_order_relaxed);
    return result;
}

void ZeroHeapAllocator::resetAudioBuffer() {
    audio_offset_.store(0, std::memory_order_relaxed);
}

bool ZeroHeapAllocator::pushImuSample(const ImuOrientation& imu) {
    std::lock_guard<std::mutex> lock(imu_mutex_);
    size_t head = imu_head_.load(std::memory_order_relaxed);
    imu_ring_[head % IMU_RING_SIZE] = imu;
    imu_head_.store(head + 1, std::memory_order_release);
    return true;
}

bool ZeroHeapAllocator::popLatestImuSample(ImuOrientation& out_imu) {
    std::lock_guard<std::mutex> lock(imu_mutex_);
    size_t head = imu_head_.load(std::memory_order_acquire);
    if (head == 0) return false;
    out_imu = imu_ring_[(head - 1) % IMU_RING_SIZE];
    return true;
}

void ZeroHeapAllocator::flushAndRelease() {
    if (initialized_) {
        std::memset(raw_pool_memory_, 0, total_pool_size_);
        frame_write_idx_.store(0);
        frame_read_idx_.store(0);
        scratchpad_offset_.store(0);
        audio_offset_.store(0);
        imu_head_.store(0);
        imu_tail_.store(0);
        initialized_ = false;
    }
}

} // namespace orbisnav
