import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'orbisnav_bindings.dart';

enum ThermalState {
  nominal,   // < 40C: 30 FPS
  warm,      // 40-43C: 20 FPS (skip 1 of 3)
  hot,       // 43-46C: 15 FPS (hazard prioritized over OCR)
  critical   // >= 46C: 10 FPS (haptic-only spatial pulses)
}

class OrbisNavController {
  final OrbisNavBindings _bindings;
  bool _isInitialized = false;

  OrbisNavController({OrbisNavBindings? bindings})
      : _bindings = bindings ?? OrbisNavBindings();

  bool initialize() {
    _isInitialized = _bindings.init();
    return _isInitialized;
  }

  void shutdown() {
    _bindings.shutdown();
    _isInitialized = false;
  }

  bool get isInitialized => _isInitialized;
  int get bootDurationMs => _bindings.getBootDurationMs();
  int get memoryUsedBytes => _bindings.getMemoryUsedBytes();
  bool get isMemoryCompliant => _bindings.isWithinMemoryBudget();
  int get targetFps => _bindings.getTargetFps();
  bool get isHazardActive => _bindings.isHazardActive();
  bool get isConversationSuspended => _bindings.isConversationSuspended();

  ThermalState get thermalState {
    final band = _bindings.getThermalBand();
    switch (band) {
      case 0: return ThermalState.nominal;
      case 1: return ThermalState.warm;
      case 2: return ThermalState.hot;
      case 3: return ThermalState.critical;
      default: return ThermalState.nominal;
    }
  }

  void updateImu({required double pitchDeg, required double rollDeg, required double yawDeg, required int timestampNs}) {
    _bindings.ingestImu(pitchDeg, rollDeg, yawDeg, timestampNs);
  }

  void setTemperature(double celsius) {
    _bindings.setSoCTemperature(celsius);
  }

  void ingestDetection({
    required double xMin,
    required double yMin,
    required double xMax,
    required double yMax,
    required double confidence,
    required int classId,
    required int timestampNs,
  }) {
    _bindings.ingestDetection(xMin, yMin, xMax, yMax, confidence, classId, timestampNs);
  }

  void addMapNode({
    required int id,
    required String name,
    required double x,
    required double y,
    required String plaqueLabel,
  }) {
    final namePtr = name.toNativeUtf8();
    final plaquePtr = plaqueLabel.toNativeUtf8();
    try {
      _bindings.addMapNode(id, namePtr, x, y, plaquePtr);
    } finally {
      malloc.free(namePtr);
      malloc.free(plaquePtr);
    }
  }

  void addMapEdge(int fromId, int toId, double distance) {
    _bindings.addMapEdge(fromId, toId, distance);
  }

  List<int> computePath(int startId, int goalId) {
    final outBuf = malloc<ffi.Uint32>(64);
    try {
      final count = _bindings.computePath(startId, goalId, outBuf, 64);
      final list = <int>[];
      for (var i = 0; i < count; i++) {
        list.add(ffi.Uint32Pointer(outBuf)[i]);
      }
      return list;
    } finally {
      malloc.free(outBuf);
    }
  }

  int getClockDirection(int targetNodeId) {
    return _bindings.getClockDirection(targetNodeId);
  }

  void stepPdr(double stepLengthMeters, double headingRad) {
    _bindings.ingestPdrStep(stepLengthMeters, headingRad);
  }

  bool snapOcr(String detectedText) {
    final textPtr = detectedText.toNativeUtf8();
    try {
      return _bindings.ingestOcrReading(textPtr);
    } finally {
      malloc.free(textPtr);
    }
  }

  void startDialogue(String query, String response) {
    final qPtr = query.toNativeUtf8();
    final rPtr = response.toNativeUtf8();
    try {
      _bindings.setConversation(qPtr, rPtr);
    } finally {
      malloc.free(qPtr);
      malloc.free(rPtr);
    }
  }

  void updateConversationLifecycle(int timestampNs) {
    _bindings.updateConversation(timestampNs);
  }

  void setBattery(int percent) {
    _bindings.setBatteryPercent(percent);
  }
}
