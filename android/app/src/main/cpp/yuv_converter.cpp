#include "yuv_converter.h"
#include "zero_heap_buffer.h"
#include <algorithm>

namespace orbisnav {

void YuvConverter::ConvertYuv420ToRgbZeroCopy(
    const uint8_t* __restrict__ yPlane,
    const uint8_t* __restrict__ uPlane,
    const uint8_t* __restrict__ vPlane,
    int width,
    int height,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
    uint8_t* __restrict__ outRgb
) {
    size_t outIdx = 0;

    for (int j = 0; j < height; ++j) {
        const uint8_t* yRow = yPlane + (j * yRowStride);
        const int uvRowIdx = (j >> 1) * uvRowStride;
        const uint8_t* uRow = uPlane + uvRowIdx;
        const uint8_t* vRow = vPlane + uvRowIdx;

        for (int i = 0; i < width; ++i) {
            const int yVal = static_cast<int>(yRow[i]);
            const int uvColIdx = (i >> 1) * uvPixelStride;
            const int uVal = static_cast<int>(uRow[uvColIdx]) - 128;
            const int vVal = static_cast<int>(vRow[uvColIdx]) - 128;

            // Integer fixed-point arithmetic approximation (BT.601 standard)
            const int c = yVal - 16;
            const int r = std::clamp((298 * c + 409 * vVal + 128) >> 8, 0, 255);
            const int g = std::clamp((298 * c - 100 * uVal - 208 * vVal + 128) >> 8, 0, 255);
            const int b = std::clamp((298 * c + 516 * uVal + 128) >> 8, 0, 255);

            outRgb[outIdx++] = static_cast<uint8_t>(r);
            outRgb[outIdx++] = static_cast<uint8_t>(g);
            outRgb[outIdx++] = static_cast<uint8_t>(b);
        }
    }
}

void YuvConverter::DownscaleToModelTensor(
    const uint8_t* __restrict__ srcRgb,
    int srcWidth,
    int srcHeight,
    uint8_t* __restrict__ dstTensor
) {
    const float xRatio = static_cast<float>(srcWidth) / static_cast<float>(TENSOR_WIDTH);
    const float yRatio = static_cast<float>(srcHeight) / static_cast<float>(TENSOR_HEIGHT);

    size_t dstIdx = 0;
    for (size_t y = 0; y < TENSOR_HEIGHT; ++y) {
        const int srcY = static_cast<int>(y * yRatio);
        const size_t srcRowOffset = srcY * srcWidth * 3;

        for (size_t x = 0; x < TENSOR_WIDTH; ++x) {
            const int srcX = static_cast<int>(x * xRatio);
            const size_t pixelOffset = srcRowOffset + (srcX * 3);

            // Copy RGB channels
            dstTensor[dstIdx++] = srcRgb[pixelOffset];
            dstTensor[dstIdx++] = srcRgb[pixelOffset + 1];
            dstTensor[dstIdx++] = srcRgb[pixelOffset + 2];
        }
    }
}

} // namespace orbisnav
