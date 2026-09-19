#pragma once

#include <cstdint>
#include <cstddef>
#include <atomic>
#include <vector>

namespace orbisnav {

// Static constraints complying with Core System Laws
constexpr size_t MAX_FRAME_WIDTH = 1920;
constexpr size_t MAX_FRAME_HEIGHT = 1080;
constexpr size_t RGB_BUFFER_SIZE = MAX_FRAME_WIDTH * MAX_FRAME_HEIGHT * 3; // ~6.22 MB
constexpr size_t TENSOR_WIDTH = 640;
constexpr size_t TENSOR_HEIGHT = 640;
constexpr size_t TENSOR_CHANNELS = 3;
constexpr size_t TENSOR_ELEMENTS = TENSOR_WIDTH * TENSOR_HEIGHT * TENSOR_CHANNELS; // 1.22 MB
constexpr size_t RING_BUFFER_SLOTS = 3;
constexpr size_t MAX_DETECTIONS = 32;

// Detection output representation
struct DetectionResult {
    float xMin;
    float yMin;
    float xMax;
    float yMax;
    float confidence;
    int32_t classId; // 0: Person, 1: Vehicle, 2: Stairs, 3: Obstacle, 4: Plaque
    float distanceMeters;
    float ttcSeconds;
    bool isHazard;
    uint8_t priorityLevel; // 0: Critical, 1: Safety, 2: Nav, 3: Context
};

// Static Zero-Heap Memory Ring Buffer (< 180MB total memory footprint)
struct ZeroHeapRingBuffer {
    uint8_t rgbBuffers[RING_BUFFER_SLOTS][RGB_BUFFER_SIZE];
    uint8_t tensorInputBuffers[RING_BUFFER_SLOTS][TENSOR_ELEMENTS];
    DetectionResult detectionSlots[RING_BUFFER_SLOTS][MAX_DETECTIONS];
    uint32_t detectionCounts[RING_BUFFER_SLOTS];
    std::atomic<size_t> writeIndex{0};
    std::atomic<size_t> readIndex{0};
};

class ZeroHeapManager {
public:
    static bool Initialize();
    static void Reset();
    static size_t AcquireNextWriteSlot();
    static uint8_t* GetRgbBuffer(size_t slot);
    static uint8_t* GetTensorBuffer(size_t slot);
    static DetectionResult* GetDetectionSlot(size_t slot);
    static void SetDetectionCount(size_t slot, uint32_t count);
    static uint32_t GetDetectionCount(size_t slot);
    static size_t GetTotalMemoryFootprint();
};

} // namespace orbisnav
