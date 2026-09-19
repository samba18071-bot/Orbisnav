import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// Native typedefs
typedef NativeInit = ffi.Bool Function();
typedef NativeShutdown = ffi.Void Function();
typedef NativeIngestImu = ffi.Void Function(ffi.Float, ffi.Float, ffi.Float, ffi.Uint64);
typedef NativeSetSoCTemp = ffi.Void Function(ffi.Float);
typedef NativeIngestDetection = ffi.Void Function(ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Uint16, ffi.Uint64);
typedef NativeAddMapNode = ffi.Void Function(ffi.Uint32, ffi.Pointer<Utf8>, ffi.Float, ffi.Float, ffi.Pointer<Utf8>);
typedef NativeAddMapEdge = ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Float);
typedef NativeComputePath = ffi.Int32 Function(ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Uint32>, ffi.IntPtr);
typedef NativeGetClockDirection = ffi.Uint8 Function(ffi.Uint32);
typedef NativeIngestPdrStep = ffi.Void Function(ffi.Float, ffi.Float);
typedef NativeIngestOcrReading = ffi.Bool Function(ffi.Pointer<Utf8>);
typedef NativeSetConversation = ffi.Void Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef NativeUpdateConversation = ffi.Void Function(ffi.Uint64);
typedef NativeSetBattery = ffi.Void Function(ffi.Uint32);
typedef NativeGetBootDurationMs = ffi.Uint64 Function();
typedef NativeGetMemoryUsedBytes = ffi.IntPtr Function();
typedef NativeIsWithinMemoryBudget = ffi.Bool Function();
typedef NativeGetTargetFps = ffi.Uint32 Function();
typedef NativeGetThermalBand = ffi.Uint8 Function();
typedef NativeIsHazardActive = ffi.Bool Function();
typedef NativeIsConversationSuspended = ffi.Bool Function();

// Dart typedefs
typedef DartInit = bool Function();
typedef DartShutdown = void Function();
typedef DartIngestImu = void Function(double, double, double, int);
typedef DartSetSoCTemp = void Function(double);
typedef DartIngestDetection = void Function(double, double, double, double, double, int, int);
typedef DartAddMapNode = void Function(int, ffi.Pointer<Utf8>, double, double, ffi.Pointer<Utf8>);
typedef DartAddMapEdge = void Function(int, int, double);
typedef DartComputePath = int Function(int, int, ffi.Pointer<ffi.Uint32>, int);
typedef DartGetClockDirection = int Function(int);
typedef DartIngestPdrStep = void Function(double, double);
typedef DartIngestOcrReading = bool Function(ffi.Pointer<Utf8>);
typedef DartSetConversation = void Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef DartUpdateConversation = void Function(int);
typedef DartSetBattery = void Function(int);
typedef DartGetBootDurationMs = int Function();
typedef DartGetMemoryUsedBytes = int Function();
typedef DartIsWithinMemoryBudget = bool Function();
typedef DartGetTargetFps = int Function();
typedef DartGetThermalBand = int Function();
typedef DartIsHazardActive = bool Function();
typedef DartIsConversationSuspended = bool Function();

class OrbisNavBindings {
  late ffi.DynamicLibrary _dylib;

  late DartInit init;
  late DartShutdown shutdown;
  late DartIngestImu ingestImu;
  late DartSetSoCTemp setSoCTemperature;
  late DartIngestDetection ingestDetection;
  late DartAddMapNode addMapNode;
  late DartAddMapEdge addMapEdge;
  late DartComputePath computePath;
  late DartGetClockDirection getClockDirection;
  late DartIngestPdrStep ingestPdrStep;
  late DartIngestOcrReading ingestOcrReading;
  late DartSetConversation setConversation;
  late DartUpdateConversation updateConversation;
  late DartSetBattery setBatteryPercent;
  late DartGetBootDurationMs getBootDurationMs;
  late DartGetMemoryUsedBytes getMemoryUsedBytes;
  late DartIsWithinMemoryBudget isWithinMemoryBudget;
  late DartGetTargetFps getTargetFps;
  late DartGetThermalBand getThermalBand;
  late DartIsHazardActive isHazardActive;
  late DartIsConversationSuspended isConversationSuspended;

  OrbisNavBindings({String? libraryPath}) {
    final path = libraryPath ?? _getDefaultLibraryPath();
    _dylib = ffi.DynamicLibrary.open(path);

    init = _dylib.lookupFunction<NativeInit, DartInit>('orbisnav_init');
    shutdown = _dylib.lookupFunction<NativeShutdown, DartShutdown>('orbisnav_shutdown');
    ingestImu = _dylib.lookupFunction<NativeIngestImu, DartIngestImu>('orbisnav_ingest_imu');
    setSoCTemperature = _dylib.lookupFunction<NativeSetSoCTemp, DartSetSoCTemp>('orbisnav_set_soc_temperature');
    ingestDetection = _dylib.lookupFunction<NativeIngestDetection, DartIngestDetection>('orbisnav_ingest_detection');
    addMapNode = _dylib.lookupFunction<NativeAddMapNode, DartAddMapNode>('orbisnav_add_map_node');
    addMapEdge = _dylib.lookupFunction<NativeAddMapEdge, DartAddMapEdge>('orbisnav_add_map_edge');
    computePath = _dylib.lookupFunction<NativeComputePath, DartComputePath>('orbisnav_compute_path');
    getClockDirection = _dylib.lookupFunction<NativeGetClockDirection, DartGetClockDirection>('orbisnav_get_clock_direction');
    ingestPdrStep = _dylib.lookupFunction<NativeIngestPdrStep, DartIngestPdrStep>('orbisnav_ingest_pdr_step');
    ingestOcrReading = _dylib.lookupFunction<NativeIngestOcrReading, DartIngestOcrReading>('orbisnav_ingest_ocr_reading');
    setConversation = _dylib.lookupFunction<NativeSetConversation, DartSetConversation>('orbisnav_set_conversation');
    updateConversation = _dylib.lookupFunction<NativeUpdateConversation, DartUpdateConversation>('orbisnav_update_conversation_lifecycle');
    setBatteryPercent = _dylib.lookupFunction<NativeSetBattery, DartSetBattery>('orbisnav_set_battery_percent');
    getBootDurationMs = _dylib.lookupFunction<NativeGetBootDurationMs, DartGetBootDurationMs>('orbisnav_get_boot_duration_ms');
    getMemoryUsedBytes = _dylib.lookupFunction<NativeGetMemoryUsedBytes, DartGetMemoryUsedBytes>('orbisnav_get_memory_used_bytes');
    isWithinMemoryBudget = _dylib.lookupFunction<NativeIsWithinMemoryBudget, DartIsWithinMemoryBudget>('orbisnav_is_within_memory_budget');
    getTargetFps = _dylib.lookupFunction<NativeGetTargetFps, DartGetTargetFps>('orbisnav_get_target_fps');
    getThermalBand = _dylib.lookupFunction<NativeGetThermalBand, DartGetThermalBand>('orbisnav_get_thermal_band');
    isHazardActive = _dylib.lookupFunction<NativeIsHazardActive, DartIsHazardActive>('orbisnav_is_hazard_active');
    isConversationSuspended = _dylib.lookupFunction<NativeIsConversationSuspended, DartIsConversationSuspended>('orbisnav_is_conversation_suspended');
  }

  static String _getDefaultLibraryPath() {
    if (Platform.isMacOS) {
      return './build/liborbisnav.dylib';
    } else if (Platform.isLinux) {
      return './build/liborbisnav.so';
    } else if (Platform.isWindows) {
      return './build/orbisnav.dll';
    }
    return 'liborbisnav.so';
  }
}
