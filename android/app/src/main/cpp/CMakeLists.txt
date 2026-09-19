cmake_minimum_required(VERSION 3.22.1)
project(native_vision_core LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Compiler optimization flags for mobile ARM64-v8a
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -ffast-math -flto -Wall -Wextra -pthread")

# Core engine include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
)

set(CORE_SOURCES
    vision_engine.cpp
    yuv_converter.cpp
    zero_heap_buffer.cpp
)

# Build unified native shared library targets
add_library(native_vision_core SHARED ${CORE_SOURCES})
add_library(vision_engine SHARED ${CORE_SOURCES})

# Find standard Android system libraries
find_library(LOG_LIB log)
find_library(ANDROID_LIB android)
find_library(JNIGRAPHICS_LIB jnigraphics)

# Link native system libraries
target_link_libraries(
    native_vision_core
    ${LOG_LIB}
    ${ANDROID_LIB}
    ${JNIGRAPHICS_LIB}
)

target_link_libraries(
    vision_engine
    ${LOG_LIB}
    ${ANDROID_LIB}
    ${JNIGRAPHICS_LIB}
)
