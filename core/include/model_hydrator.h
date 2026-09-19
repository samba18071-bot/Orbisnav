#ifndef MODEL_HYDRATOR_H
#define MODEL_HYDRATOR_H

#include "orbisnav_types.h"
#include <string>
#include <vector>
#include <cstdint>

namespace orbisnav {

struct ModelMetadata {
    std::string name;
    std::string format;      // "INT8 ONNX"
    size_t weight_size_bytes{0};
    bool is_hydrated{false};
    bool is_offline{true};
    uint8_t* memory_mapped_ptr{nullptr};
};

class ModelHydrator {
public:
    ModelHydrator();
    ~ModelHydrator();

    // Hydrates both YOLOv8-Nano and PaddleOCR into inference scratchpad
    // Asserts 100% offline (no sockets opened) and completes in <500ms
    bool hydrateModels();

    // Inspect status
    bool isYoloHydrated() const { return yolo_meta_.is_hydrated; }
    bool isOcrHydrated() const { return ocr_meta_.is_hydrated; }
    bool isFullyOffline() const { return yolo_meta_.is_offline && ocr_meta_.is_offline; }

    // Unload models (e.g. for low battery override)
    void unloadOcr();
    void unloadYolo();
    void unloadAll();

    const ModelMetadata& getYoloMeta() const { return yolo_meta_; }
    const ModelMetadata& getOcrMeta() const { return ocr_meta_; }

private:
    ModelMetadata yolo_meta_;
    ModelMetadata ocr_meta_;
    bool verifyOfflineCompliance();
};

} // namespace orbisnav

#endif // MODEL_HYDRATOR_H
