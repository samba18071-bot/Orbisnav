#include "zero_heap_buffer.h"
#include <cstring>
#include <android/log.h>

#define TAG "ZeroHeapBuffer"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

namespace orbisnav {

// Statically allocated zero-heap memory buffer in BSS/RAM (< 180MB total footprint)
static ZeroHeapRingBuffer g_ringBuffer;
static std::atomic<bool> g_isInitialized{false};

bool ZeroHeapManager::Initialize() {
    std::memset(&g_ringBuffer, 0, sizeof(g_ringBuffer));
    g_ringBuffer.writeIndex.store(0);
    g_ringBuffer.readIndex.store(0);
    g_isInitialized.store(true);

    const size_t totalBytes = sizeof(g_ringBuffer);
    LOGI("Zero-heap static ring buffers allocated successfully. Total size: %zu bytes (%.2f MB)",
         totalBytes, static_cast<double>(totalBytes) / (1024.0 * 1024.0));
    return true;
}

void ZeroHeapManager::Reset() {
    std::memset(&g_ringBuffer, 0, sizeof(g_ringBuffer));
    g_ringBuffer.writeIndex.store(0);
    g_ringBuffer.readIndex.store(0);
    g_isInitialized.store(false);
    LOGI("Zero-heap static ring buffer reset.");
}

size_t ZeroHeapManager::AcquireNextWriteSlot() {
    return g_ringBuffer.writeIndex.fetch_add(1) % RING_BUFFER_SLOTS;
}

uint8_t* ZeroHeapManager::GetRgbBuffer(size_t slot) {
    return g_ringBuffer.rgbBuffers[slot % RING_BUFFER_SLOTS];
}

uint8_t* ZeroHeapManager::GetTensorBuffer(size_t slot) {
    return g_ringBuffer.tensorInputBuffers[slot % RING_BUFFER_SLOTS];
}

DetectionResult* ZeroHeapManager::GetDetectionSlot(size_t slot) {
    return g_ringBuffer.detectionSlots[slot % RING_BUFFER_SLOTS];
}

void ZeroHeapManager::SetDetectionCount(size_t slot, uint32_t count) {
    g_ringBuffer.detectionCounts[slot % RING_BUFFER_SLOTS] = count;
}

uint32_t ZeroHeapManager::GetDetectionCount(size_t slot) {
    return g_ringBuffer.detectionCounts[slot % RING_BUFFER_SLOTS];
}

size_t ZeroHeapManager::GetTotalMemoryFootprint() {
    return sizeof(g_ringBuffer);
}

} // namespace orbisnav
