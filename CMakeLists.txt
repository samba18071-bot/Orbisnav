cmake_minimum_required(VERSION 3.16)
project(orbisnav LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include_directories(core/include)

set(ORBISNAV_SOURCES
    core/src/zero_heap_allocator.cpp
    core/src/model_hydrator.cpp
    core/src/thermal_governor.cpp
    core/src/perception_preemption.cpp
    core/src/navigation_engine.cpp
    core/src/audio_governor.cpp
    core/src/power_and_lifecycle.cpp
    core/src/wearable_transport.cpp
    core/src/orbisnav_engine.cpp
    core/src/orbisnav_api.cpp
)

# Build Shared Library for FFI
add_library(orbisnav SHARED ${ORBISNAV_SOURCES})
target_link_libraries(orbisnav PRIVATE Threads::Threads)

# Find threads
find_package(Threads REQUIRED)

# Build Verification Test Executable
add_executable(orbisnav_test
    ${ORBISNAV_SOURCES}
    test/orbisnav_core_test.cpp
)
target_link_libraries(orbisnav_test PRIVATE Threads::Threads)

# Build AI-Eyes Comprehensive Point-to-Point Audit Test Executable
add_executable(ai_eyes_audit_test
    ${ORBISNAV_SOURCES}
    test/ai_eyes_audit_test.cpp
)
target_link_libraries(ai_eyes_audit_test PRIVATE Threads::Threads)

enable_testing()
add_test(NAME OrbisNavCoreTests COMMAND orbisnav_test)
add_test(NAME AiEyesAuditTests COMMAND ai_eyes_audit_test)

