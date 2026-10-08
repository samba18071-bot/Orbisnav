#!/usr/bin/env bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${SCRIPT_DIR}/build"
mkdir -p "${BUILD_DIR}"

echo "[BUILD] Compiling OrbisNav Native Shared Library and Verification Suite..."

clang++ -std=c++17 -O3 -Wall -Wextra -pthread \
    -I"${SCRIPT_DIR}/core/include" \
    "${SCRIPT_DIR}/core/src/zero_heap_allocator.cpp" \
    "${SCRIPT_DIR}/core/src/model_hydrator.cpp" \
    "${SCRIPT_DIR}/core/src/thermal_governor.cpp" \
    "${SCRIPT_DIR}/core/src/perception_preemption.cpp" \
    "${SCRIPT_DIR}/core/src/navigation_engine.cpp" \
    "${SCRIPT_DIR}/core/src/audio_governor.cpp" \
    "${SCRIPT_DIR}/core/src/power_and_lifecycle.cpp" \
    "${SCRIPT_DIR}/core/src/wearable_transport.cpp" \
    "${SCRIPT_DIR}/core/src/orbisnav_engine.cpp" \
    "${SCRIPT_DIR}/core/src/orbisnav_api.cpp" \
    "${SCRIPT_DIR}/test/orbisnav_core_test.cpp" \
    -o "${BUILD_DIR}/orbisnav_test"

# Also build dynamic library for FFI bindings (dylib on macOS)
clang++ -std=c++17 -O3 -Wall -Wextra -pthread -dynamiclib \
    -I"${SCRIPT_DIR}/core/include" \
    "${SCRIPT_DIR}/core/src/zero_heap_allocator.cpp" \
    "${SCRIPT_DIR}/core/src/model_hydrator.cpp" \
    "${SCRIPT_DIR}/core/src/thermal_governor.cpp" \
    "${SCRIPT_DIR}/core/src/perception_preemption.cpp" \
    "${SCRIPT_DIR}/core/src/navigation_engine.cpp" \
    "${SCRIPT_DIR}/core/src/audio_governor.cpp" \
    "${SCRIPT_DIR}/core/src/power_and_lifecycle.cpp" \
    "${SCRIPT_DIR}/core/src/wearable_transport.cpp" \
    "${SCRIPT_DIR}/core/src/orbisnav_engine.cpp" \
    "${SCRIPT_DIR}/core/src/orbisnav_api.cpp" \
    -o "${BUILD_DIR}/liborbisnav.dylib"

echo "[BUILD] Build succeeded!"
echo "  Test binary: ${BUILD_DIR}/orbisnav_test"
echo "  Shared library: ${BUILD_DIR}/liborbisnav.dylib"
