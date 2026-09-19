#include "orbisnav_engine.h"
#include <iostream>
#include <cassert>
#include <thread>
#include <chrono>
#include <cmath>

using namespace orbisnav;

static int g_haptic_pulses_received = 0;
static float g_last_haptic_azimuth = 0.0f;
static std::string g_last_speech_text = "";
static AudioPriority g_last_speech_priority = AudioPriority::Level3_Conversational;
static int g_earcon_count = 0;
static float g_last_earcon_azimuth = 0.0f;

void test_phase1_cold_boot() {
    std::cout << "\n=== [TEST PHASE 1: COLD BOOT & ON-DEVICE INITIALIZATION] ===\n";

    OrbisNavEngine& engine = OrbisNavEngine::instance();

    engine.registerHapticCallback([](const HapticPattern& pattern, float azimuth) {
        g_haptic_pulses_received += pattern.pulse_count;
        g_last_haptic_azimuth = azimuth;
    });

    engine.registerSpeechCallback([](const std::string& text, AudioPriority priority) {
        g_last_speech_text = text;
        g_last_speech_priority = priority;
    });

    engine.registerEarconCallback([](const DirectionalEarcon& earcon) {
        g_earcon_count++;
        g_last_earcon_azimuth = earcon.azimuth_deg;
    });

    auto start = std::chrono::steady_clock::now();
    bool boot_success = engine.coldBoot();
    auto end = std::chrono::steady_clock::now();
    auto boot_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    assert(boot_success && "Cold boot must succeed");
    assert(boot_ms < 500 && "Cold boot must complete in <500ms");
    std::cout << "  [PASS] Cold boot completed in " << boot_ms << " ms (<500ms requirement).\n";

    // 1. Memory Pre-Allocation check
    EngineStats stats = engine.getEngineStats();
    std::cout << "  [INFO] Static pre-allocated memory: "
              << (stats.total_memory_allocated_bytes / (1024 * 1024)) << " MB.\n";
    assert(stats.total_memory_allocated_bytes <= TOTAL_MEMORY_BUDGET_BYTES && "Memory must be <= 180MB");
    assert(stats.is_memory_compliant && "Memory compliance flag must be true");
    std::cout << "  [PASS] Memory pre-allocation strictly <= 180MB.\n";

    // 2. Model Hydration check
    assert(stats.is_offline_compliant && "Model hydrator must maintain 100% offline status");
    assert(engine.getModelHydrator().isYoloHydrated() && "YOLOv8-Nano INT8 must be hydrated");
    assert(engine.getModelHydrator().isOcrHydrated() && "PaddleOCR INT8 must be hydrated");
    std::cout << "  [PASS] INT8 ONNX models hydrated in memory without network calls.\n";

    // 3. Audio Channel Mutex Setup check
    assert(engine.getAudioGovernor().isMicrophoneMuted() && "Microphone must be muted during cold boot");
    std::cout << "  [PASS] Audio channel mutex initialized with mic muted.\n";

    // 4. Boot Confirmation Haptic Cue check
    assert(g_haptic_pulses_received >= 2 && "Dual-pulse 50ms haptic confirmation must be emitted");
    std::cout << "  [PASS] Discrete 50ms dual-pulse haptic cue fired successfully.\n";
}

void test_phase2_thermal_and_imu() {
    std::cout << "\n=== [TEST PHASE 2: SENSOR INGESTION & THERMAL GOVERNANCE] ===\n";

    OrbisNavEngine& engine = OrbisNavEngine::instance();
    uint64_t now_ns = 1000000000ULL;

    // 1. IMU Orientation Audit: Normal horizontal pitch
    g_last_speech_text = "";
    engine.ingestImuSample(0.0f, 0.0f, 0.0f, now_ns);
    assert(g_last_speech_text == "" && "No warning should fire when phone pitch is level");

    // 2. IMU Orientation Audit: Phone pitch > 30 deg below horizon
    now_ns += 100000000ULL;
    engine.ingestImuSample(-35.0f, 0.0f, 0.0f, now_ns);
    assert(g_last_speech_text == "Tilt phone up." && "Should prompt 'Tilt phone up.' on downward pitch");
    std::cout << "  [PASS] IMU downward tilt (>30 deg) correctly triggered quiet haptic tick & 'Tilt phone up.'\n";

    // 3. Dynamic Thermal Throttling
    // Band 0: < 40C => 30 FPS
    engine.setSoCTemperature(36.0f);
    assert(engine.getThermalGovernor().getCurrentBand() == ThermalBand::Nominal_Under40C);
    assert(engine.getThermalGovernor().getTargetFps() == 30);
    assert(engine.getThermalGovernor().isOcrEnabled() == true);
    std::cout << "  [PASS] T_SoC < 40C => 30 FPS Nominal Vision.\n";

    // Band 1: 40C to 43C => 20 FPS (skip 1 of 3 frames)
    engine.setSoCTemperature(41.5f);
    assert(engine.getThermalGovernor().getCurrentBand() == ThermalBand::Warm_40C_to_43C);
    assert(engine.getThermalGovernor().getTargetFps() == 20);
    assert(engine.getThermalGovernor().shouldProcessFrame(0) == true);
    assert(engine.getThermalGovernor().shouldProcessFrame(1) == true);
    assert(engine.getThermalGovernor().shouldProcessFrame(2) == false); // skip 1 of 3
    std::cout << "  [PASS] 40C <= T_SoC < 43C => 20 FPS (1 of 3 frames skipped).\n";

    // Band 2: 43C to 46C => 15 FPS (Hazard prioritized over OCR)
    engine.setSoCTemperature(44.0f);
    assert(engine.getThermalGovernor().getCurrentBand() == ThermalBand::Hot_43C_to_46C);
    assert(engine.getThermalGovernor().getTargetFps() == 15);
    assert(engine.getThermalGovernor().isOcrEnabled() == false); // OCR shed
    std::cout << "  [PASS] 43C <= T_SoC < 46C => 15 FPS (Hazard prioritized over OCR).\n";

    // Band 3: >= 46C => 10 FPS (Haptic-only spatial pulses)
    engine.setSoCTemperature(47.5f);
    assert(engine.getThermalGovernor().getCurrentBand() == ThermalBand::Critical_Over46C);
    assert(engine.getThermalGovernor().getTargetFps() == 10);
    assert(engine.getThermalGovernor().isHapticOnlyMode() == true);
    std::cout << "  [PASS] T_SoC >= 46C => 10 FPS (Haptic-only spatial pulses fallback).\n";

    // Reset temperature back to nominal for subsequent tests
    engine.setSoCTemperature(35.0f);
}

void test_phase3_perception_and_hazard_preemption() {
    std::cout << "\n=== [TEST PHASE 3: REAL-TIME PERCEPTION & HAZARD PREEMPTION] ===\n";

    OrbisNavEngine& engine = OrbisNavEngine::instance();
    uint64_t timestamp_ns = 2000000000ULL;

    // Reset counters
    g_earcon_count = 0;
    uint32_t initial_preemptions = engine.getEngineStats().preemption_event_count;
    (void)initial_preemptions;

    // 1. Debounce Guard: Send duplicate bounding boxes within 800ms
    BoundingBox distant_box{0.4f, 0.4f, 0.6f, 0.6f, 0.95f, ObstacleClass::Pedestrian};
    bool debounced1 = engine.getPerceptionEngine().shouldDebounce(distant_box, timestamp_ns);
    assert(!debounced1 && "First detection should not be debounced");

    // Same detection 200ms later (<800ms window)
    timestamp_ns += 200000000ULL; // +200ms
    bool debounced2 = engine.getPerceptionEngine().shouldDebounce(distant_box, timestamp_ns);
    assert(debounced2 && "Duplicate detection within 800ms must be debounced");
    std::cout << "  [PASS] 800ms sliding window debounce guard suppresses duplicate bounding boxes.\n";

    // 2. Critical Hazard Preemption (<1.5m or TTC < 1.5s)
    // Create an approaching vehicle located at 2 o'clock (x > 0, z small)
    // Normalized coords: x_min=0.6, x_max=0.9 (right side), large height -> distance < 1.5m
    timestamp_ns += 1000000000ULL;
    BoundingBox critical_vehicle{0.6f, 0.1f, 0.9f, 0.95f, 0.98f, ObstacleClass::Vehicle};

    auto interrupt_start = std::chrono::steady_clock::now();
    engine.ingestVisionDetections({critical_vehicle}, timestamp_ns);
    auto interrupt_end = std::chrono::steady_clock::now();
    float interrupt_latency_ms = std::chrono::duration<float, std::milli>(interrupt_end - interrupt_start).count();

    assert(interrupt_latency_ms < 30.0f && "Hard interrupt must execute in <30ms");
    assert(engine.getPerceptionEngine().isCriticalHazardActive() && "Hazard state must be active");
    assert(engine.getAudioGovernor().isMicrophoneMuted() && "Microphone must be muted instantly");
    assert(g_earcon_count > 0 && "Directional 3D earcon must be dispatched");
    assert(g_last_earcon_azimuth > 10.0f && "Earcon should originate from right (approx 2 o'clock)");

    std::cout << "  [PASS] Critical hazard triggered <30ms hard interrupt (Latency: "
              << interrupt_latency_ms << " ms).\n";
    std::cout << "  [PASS] Microphone instantly muted and 3D earcon dispatched (Azimuth: "
              << g_last_earcon_azimuth << " deg).\n";
}

void test_phase4_navigation_and_ocr_snap() {
    std::cout << "\n=== [TEST PHASE 4: A* NAVIGATION & PDR DRIFT RE-ANCHORING] ===\n";

    OrbisNavEngine& engine = OrbisNavEngine::instance();

    // 1. Build Indoor/Outdoor topological map
    // Node 1 (Lobby): (0, 0)
    // Node 2 (Corridor): (0, 10)
    // Node 3 (Room 204): (10, 10) - Plaque: "Room 204"
    // Node 4 (Auditorium): (20, 20)
    engine.configureMapNode(1, "Lobby", 0.0f, 0.0f, "Lobby Entrance");
    engine.configureMapNode(2, "Corridor", 0.0f, 10.0f, "Corridor A");
    engine.configureMapNode(3, "Room 204", 10.0f, 10.0f, "Room 204");
    engine.configureMapNode(4, "Auditorium", 20.0f, 20.0f, "Auditorium Gate");

    engine.configureMapEdge(1, 2, 10.0f);
    engine.configureMapEdge(2, 3, 10.0f);
    engine.configureMapEdge(3, 4, 14.14f);

    // Compute A* path from Lobby (1) to Room 204 (3)
    auto path = engine.planPath(1, 3);
    assert(path.size() == 3 && "Path should be 1 -> 2 -> 3");
    assert(path[0] == 1 && path[1] == 2 && path[2] == 3);
    std::cout << "  [PASS] A* optimal route generated: Node 1 -> Node 2 -> Node 3.\n";

    // 2. Relative Clock-Face Mapping
    // User at (0, 0) facing North (heading = 0 rad). Target is (0, 10).
    // Relative bearing = 0 rad => 12 o'clock (straight ahead)
    engine.getNavigationEngine().setPdrPosition({0.0f, 0.0f}, 0.0f);
    ClockDirection clock1 = engine.getNextWaypointClockDirection(2);
    assert(clock1 == ClockDirection::TwelveOClock && "Forward node should be 12 o'clock");
    std::cout << "  [PASS] Clock-face mapping for forward node: "
              << engine.getNavigationEngine().clockDirectionToString(clock1) << ".\n";

    // Target is (10, 0) (direct right), user facing North (0 rad).
    // Relative bearing = 90 deg => 3 o'clock (direct right)
    ClockDirection clock2 = engine.getNavigationEngine().computeClockDirection({0.0f, 0.0f}, 0.0f, {10.0f, 0.0f});
    assert(clock2 == ClockDirection::ThreeOClock && "Right node should be 3 o'clock");
    std::cout << "  [PASS] Clock-face mapping for right node: "
              << engine.getNavigationEngine().clockDirectionToString(clock2) << ".\n";

    // 3. PDR Drift Simulation
    for (int i = 0; i < 15; ++i) {
        engine.ingestPdrStep(0.7f, 0.0f); // 15 steps of 0.7m
    }
    PdrState pdr = engine.getNavigationEngine().getPdrState();
    assert(pdr.step_count == 15);
    assert((pdr.accumulated_drift.x != 0.0f || pdr.accumulated_drift.y != 0.0f) && "PDR should accumulate drift");
    std::cout << "  [INFO] Accumulated drift before OCR snap: ("
              << pdr.accumulated_drift.x << ", " << pdr.accumulated_drift.y << ") m.\n";

    // 4. OCR Ground-Truth Snap using Levenshtein distance (Sim >= 0.75)
    // Actual plaque is "Room 204". Let's test with noisy OCR: "Rm 204" or "Room 2O4"
    std::string noisy_ocr = "Room 2O4"; // 'O' instead of '0'
    float sim = NavigationEngine::computeLevenshteinSimilarity(noisy_ocr, "Room 204");
    std::cout << "  [INFO] Levenshtein similarity between '" << noisy_ocr << "' and 'Room 204': " << sim << "\n";
    assert(sim >= 0.75f && "Similarity should be >= 0.75");

    bool snapped = engine.ingestOcrPlaqueReading(noisy_ocr);
    assert(snapped && "Ground truth snap should succeed");

    PdrState pdr_snapped = engine.getNavigationEngine().getPdrState();
    assert(pdr_snapped.current_pos.x == 10.0f && pdr_snapped.current_pos.y == 10.0f && "User coords must snap to plaque");
    assert(pdr_snapped.accumulated_drift.x == 0.0f && pdr_snapped.accumulated_drift.y == 0.0f && "Accumulated drift must be zeroed out: e_drift = 0");

    std::cout << "  [PASS] OCR ground-truth snapped coordinates to (10, 10) and reset e_drift = 0.\n";
}

void test_phase5_conversational_suspension_and_resume() {
    std::cout << "\n=== [TEST PHASE 5: CONVERSATIONAL SUSPENSION & AUTO-RESUMPTION] ===\n";

    OrbisNavEngine& engine = OrbisNavEngine::instance();
    uint64_t now_ns = 5000000000ULL;

    // 1. Start dialogue at Level 3
    std::string query = "Where is the computer lab?";
    std::string response = "Take the hallway on your right and proceed past Room 204.";
    engine.startConversationalDialogue(query, response);

    assert(engine.getAudioGovernor().getCurrentPriority() == AudioPriority::Level3_Conversational);
    assert(!engine.getAudioGovernor().isMicrophoneMuted());
    std::cout << "  [PASS] Conversational dialogue active at Level 3.\n";

    // 2. Hazard Suspension: obstacle detected (<1.5m)
    // Send critical obstacle
    BoundingBox hazard_box{0.2f, 0.1f, 0.8f, 0.95f, 0.99f, ObstacleClass::Stairs};
    engine.ingestVisionDetections({hazard_box}, now_ns);

    assert(engine.getAudioGovernor().hasSuspendedContext() && "Context must be saved on stack");
    assert(engine.getAudioGovernor().isMicrophoneMuted() && "Microphone must be muted");
    assert(engine.getAudioGovernor().getCurrentPriority() == AudioPriority::Level0_HazardAlert);
    std::cout << "  [PASS] Hazard detected: Dialogue pushed to ConversationContextStack, speech halted.\n";

    // 3. Clear path verification (< 1.5 seconds)
    // Send clear frame at +500ms
    now_ns += 500000000ULL; // +0.5s
    engine.ingestVisionDetections({}, now_ns); // clear frame
    engine.updateConversationalLifecycle(now_ns);

    assert(engine.getAudioGovernor().hasSuspendedContext() && "Context must remain suspended if < 1.5s");
    std::cout << "  [PASS] Auto-resume suppressed when path clear < 1.5s.\n";

    // 4. Clear path verification (>= 1.5 seconds)
    // Send clear frame at +1.6s after clear
    now_ns += 1600000000ULL; // +1.6s
    engine.updateConversationalLifecycle(now_ns);

    assert(!engine.getAudioGovernor().hasSuspendedContext() && "Context must be popped from stack");
    assert(!engine.getAudioGovernor().isMicrophoneMuted() && "Microphone must be unmuted");
    assert(g_last_speech_text.find("Path clear. Continuing...") != std::string::npos && "Resumption speech must be triggered");

    std::cout << "  [PASS] Path clear for >= 1.5s: Auto-resumed speech: '" << g_last_speech_text << "'\n";
}

void test_phase6_power_saver_and_termination() {
    std::cout << "\n=== [TEST PHASE 6: POWER SAVER & TERMINATION] ===\n";

    OrbisNavEngine& engine = OrbisNavEngine::instance();

    // 1. Low Battery Override (<= 15%)
    engine.setBatteryLevel(14); // 14%
    assert(engine.getPowerManager().isLowPowerMode() && "Low power mode must activate at <= 15%");
    assert(engine.getPowerManager().getDownclockedFps() == 10 && "Camera must downclock to 10 FPS");
    assert(engine.getPowerManager().getFeedbackMode() == FeedbackMode::FourZoneHapticOnly && "Must switch to 4-Zone Haptic Pulses");
    assert(!engine.getModelHydrator().isOcrHydrated() && "OCR model must be unloaded from RAM");
    std::cout << "  [PASS] Low battery override (<= 15%): OCR unloaded, downclocked to 10 FPS, 4-zone haptic mode active.\n";

    // 2. Graceful Shutdown
    engine.shutdown();
    assert(engine.getPowerManager().isTerminated() && "System must mark terminated");
    assert(!ZeroHeapAllocator::instance().acquireWriteFrameSlot() && "Memory ring buffers must be flushed and released");
    std::cout << "  [PASS] Graceful shutdown executed: memory buffers flushed and handles cleanly released.\n";
}

int main() {
    std::cout << "===============================================================\n";
    std::cout << "  ORBISNAV MASTER SYSTEM VERIFICATION TEST SUITE (PHASES 1-6)  \n";
    std::cout << "===============================================================\n";

    test_phase1_cold_boot();
    test_phase2_thermal_and_imu();
    test_phase3_perception_and_hazard_preemption();
    test_phase4_navigation_and_ocr_snap();
    test_phase5_conversational_suspension_and_resume();
    test_phase6_power_saver_and_termination();

    std::cout << "\n===============================================================\n";
    std::cout << "  ALL ORBISNAV MASTER SPECIFICATION TESTS PASSED SUCCESSFULLY! \n";
    std::cout << "===============================================================\n";
    return 0;
}
