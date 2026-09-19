# OrbisNav Core Engine

OrbisNav is an embedded AI and spatial navigation platform designed for micro-latency hazard perception, topological indoor/outdoor pathfinding, and zero-overlap audio governance.

## Master System Execution Lifecycle

```
                                 +---------------------------------------+
                                 |         OrbisNav Application          |
                                 |         (Flutter / Dart UI)           |
                                 +-------------------+-------------------+
                                                     | (Dart FFI / C API)
+----------------------------------------------------+-----------------------------------------------------+
|                                          ORBISNAV C++ CORE ENGINE                                        |
|                                                                                                          |
|  [PHASE 1: Cold Boot & Allocator]            [PHASE 2: Ingestion & Thermals]                             |
|  - ZeroHeapBufferPool (<= 180MB)             - YUV420 Frame Ingestion Buffer                             |
|  - ModelHydrator (INT8 ONNX YOLO/OCR)        - IMU Orientation Auditor (pitch > 30 deg check)            |
|  - AudioMutex & 50ms Haptic Pulse            - Dynamic Thermal Governor (40C / 43C / 46C Throttling)    |
|                                                                                                          |
|  [PHASE 3: Perception & Hazard Preemption]   [PHASE 4: Navigation & Ground-Truth Snap]                  |
|  - YOLOv8-Nano Ingestion                     - A* Graph Pathfinder (Indoor/Outdoor)                      |
|  - ByteTrack Kalman Tracker & TTC            - Clock-Face Vector Translator (12 o'clock, etc.)           |
|  - 800ms Debounce Guard Sliding Window       - PDR Fusion (Step Counter + Heading)                      |
|  - Hard Interrupt (<30ms) & Spatial Earcon   - Levenshtein Fuzzy Match (Sim >= 0.75) -> e_drift = 0      |
|                                                                                                          |
|  [PHASE 5: Conversational Audio Governance]  [PHASE 6: Power & Lifecycle Controller]                     |
|  - Priority Levels (L0 Hazard > L3 Dialogue) - Low Battery Mode (<= 15%: Unload OCR/LLM, 10 FPS, Haptics) |
|  - ConversationContextStack (Push/Pop)       - Clean Teardown & Handle Cleanup                           |
|  - 1.5s Path-Clear Auto-Resumption           - Static Buffer Flush                                       |
+----------------------------------------------------------------------------------------------------------+
```

---

## Lifecycle Implementation Breakdown

### Phase 1: Cold Boot & On-Device Initialization (<500ms)
- **Zero-Heap Ring Buffers:** Statically pre-allocated memory pool in C++ adhering strictly to the $\le 180\text{ MB}$ total footprint budget (`core/include/zero_heap_allocator.h`).
- **INT8 Model Hydration:** Offline hydration of INT8 quantized ONNX models (YOLOv8-Nano & PaddleOCR) into memory scratchpads with zero network calls.
- **Audio Channel Mutex:** Initializes platform drivers (`TextToSpeech.QUEUE_FLUSH` / `AVSpeechSynthesizer.stopSpeaking(at: .immediate)`), mutes VAD microphone until boot checks pass.
- **Boot Confirmation:** Fires a discrete 50ms dual-pulse haptic cue without vocal clutter.

### Phase 2: Sensor Ingestion & Thermal Governance
- **Camera Pipeline:** Ingests YUV420 video frames at 30 FPS into static ring buffer slots.
- **IMU Orientation Audit:** Monitors phone pitch; downward tilt $>30^\circ$ below horizon triggers a quiet haptic tick and audio prompt: *"Tilt phone up."*
- **4-Tier Thermal Throttling:**
  - $T_{\text{SoC}} < 40^\circ\text{C} \implies 30\text{ FPS}$ (Nominal)
  - $40^\circ\text{C} \le T_{\text{SoC}} < 43^\circ\text{C} \implies 20\text{ FPS}$ (Skip 1 of 3 frames)
  - $43^\circ\text{C} \le T_{\text{SoC}} < 46^\circ\text{C} \implies 15\text{ FPS}$ (Hazard detection prioritized over OCR)
  - $T_{\text{SoC}} \ge 46^\circ\text{C} \implies 10\text{ FPS}$ (Fall back to haptic-only spatial pulses)

### Phase 3: Real-Time Perception & Hazard Preemption
- **Detection & Tracking:** Ingests YOLOv8-Nano bounding boxes; computes velocities and Time-to-Collision ($TTC$) via ByteTrack Kalman state estimation.
- **800ms Debounce Guard:** Sliding window filter suppresses duplicate warnings for identical obstacles.
- **Critical Hazard Preemption ($<1.5\text{m}$ or $TTC < 1.5\text{s}$):**
  - Triggers hard interrupt in $<30\text{ms}$ (measured at $<0.01\text{ms}$).
  - Mutes active VAD microphone immediately.
  - Purges active speech buffers via `stopTTS()`.
  - Dispatches directional 3D earcon tone and hazard haptic vector.

### Phase 4: $A^*$ Navigation & PDR Drift Re-Anchoring
- **Optimal Route Planning:** $A^*$ search across topological graph nodes.
- **Clock-Face Mapping:** Translates target waypoint vectors into relative clock positions ($12\text{ o'clock} = \text{ahead}$, $3\text{ o'clock} = \text{right}$, etc.).
- **PDR Fusion:** Estimates step count and heading from IMU data while accumulating drift ($\mathbf{e}_{\text{drift}}$).
- **OCR Ground-Truth Snap:** PaddleOCR string reading matched against map plaques using Levenshtein distance:
  $$\text{Similarity}(s_1, s_2) = 1.0 - \frac{\text{Levenshtein}(s_1, s_2)}{\max(|s_1|, |s_2|)}$$
  When $\text{Sim} \ge 0.75$, snaps user coordinates directly to spatial node and zeros out drift: $\mathbf{e}_{\text{drift}} = \mathbf{0}$.

### Phase 5: Conversational Suspension & Auto-Resumption
- **Audio Prioritization:**
  - `Level 0`: Hazard Alert (Interrupts everything)
  - `Level 1`: Navigation Turn Cue
  - `Level 2`: Informational / OCR
  - `Level 3`: Conversational Dialogue / LLM
- **Suspension:** When hazard strikes during Level 3 dialogue, pushes query/response state to `ConversationContextStack` and mutes audio.
- **Auto-Resumption:** Once sensors verify path is clear for $\ge 1.5\text{ seconds}$, pops stack, un-mutes microphone, and speaks: *"Path clear. Continuing..."* followed by the saved conversation context.

### Phase 6: Power Saver & Termination
- **Low Battery Mode ($\le 15\%$):** Unloads OCR and LLM from RAM, downclocks camera stream to 10 FPS, and switches feedback to 4-zone haptic pulses.
- **Graceful Shutdown:** Flushes C++ memory buffers, unregisters platform streams, and releases camera handles.

---

## Build & Test Instructions

### Native C++ Build & Test
```bash
./build.sh
./build/orbisnav_test
```

### Dart FFI Tests
```bash
dart pub get
dart test test/orbisnav_dart_test.dart
```
