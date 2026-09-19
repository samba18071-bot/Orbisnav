#pragma once

#include <cstdint>
#include <cstddef>

namespace orbisnav {

class YuvConverter {
public:
    /**
     * SIMD/Integer optimized zero-heap conversion from CameraX YUV_420_888 to RGB24.
     * Direct pointer ingestion without array duplication.
     */
    static void ConvertYuv420ToRgbZeroCopy(
        const uint8_t* __restrict__ yPlane,
        const uint8_t* __restrict__ uPlane,
        const uint8_t* __restrict__ vPlane,
        int width,
        int height,
        int yRowStride,
        int uvRowStride,
        int uvPixelStride,
        uint8_t* __restrict__ outRgb
    );

    /**
     * Downscales full-resolution RGB frame directly into model input tensor (640x640x3).
     */
    static void DownscaleToModelTensor(
        const uint8_t* __restrict__ srcRgb,
        int srcWidth,
        int srcHeight,
        uint8_t* __restrict__ dstTensor
    );
};

} // namespace orbisnav
