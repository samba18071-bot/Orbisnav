import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../models/hybrid_voice_search_models.dart';

/// Monitors live device connectivity and round-trip ping latency.
/// If offline or latency > 1200ms, instructs the pipeline to run 100% on the on-device edge engine.
class NetworkHealthMonitor {
  static final NetworkHealthMonitor _instance = NetworkHealthMonitor._internal();
  factory NetworkHealthMonitor() => _instance;

  final http.Client _httpClient;
  final StreamController<NetworkHealthStatus> _statusController =
      StreamController<NetworkHealthStatus>.broadcast();

  NetworkHealthStatus _currentStatus = NetworkHealthStatus.offline();
  NetworkHealthStatus get currentStatus => _currentStatus;
  Stream<NetworkHealthStatus> get statusStream => _statusController.stream;

  bool get isOnline => _currentStatus.isOnline;
  bool get isCloudAvailable => _currentStatus.isCloudAvailable;
  int get latencyMs => _currentStatus.latencyMs;

  Timer? _pollingTimer;
  StreamSubscription? _connectivitySubscription;
  bool _isDisposed = false;

  NetworkHealthMonitor._internal({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client() {
    _init();
  }

  NetworkHealthMonitor.withClient({required http.Client httpClient})
      : _httpClient = httpClient {
    _init();
  }

  void _init() {
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
        final hasConnection = results.any((r) => r != ConnectivityResult.none);
        if (!hasConnection) {
          _updateStatus(NetworkHealthStatus.offline());
        } else {
          checkHealthNow();
        }
      });
    } catch (_) {}

    // Check health immediately and schedule periodic 10s health check
    checkHealthNow();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isDisposed) {
        checkHealthNow();
      }
    });
  }

  /// Proactively verifies network latency with an ultra-lightweight HEAD/GET probe.
  Future<NetworkHealthStatus> checkHealthNow() async {
    final stopwatch = Stopwatch()..start();
    try {
      final probeUri = Uri.parse('https://www.google.com/generate_204');
      final response = await _httpClient
          .get(probeUri)
          .timeout(const Duration(milliseconds: 1500));
      stopwatch.stop();

      final rtt = stopwatch.elapsedMilliseconds;
      final status = (response.statusCode >= 200 && response.statusCode < 400)
          ? NetworkHealthStatus.online(latencyMs: rtt)
          : NetworkHealthStatus.offline();

      _updateStatus(status);
      return status;
    } catch (_) {
      stopwatch.stop();
      final status = NetworkHealthStatus.offline();
      _updateStatus(status);
      return status;
    }
  }

  void _updateStatus(NetworkHealthStatus status) {
    if (_isDisposed) return;
    final changed = _currentStatus.isCloudAvailable != status.isCloudAvailable ||
        _currentStatus.isOnline != status.isOnline;
    _currentStatus = status;
    if (changed) {
      _statusController.add(status);
    }
  }

  void dispose() {
    _isDisposed = true;
    _pollingTimer?.cancel();
    _connectivitySubscription?.cancel();
    _statusController.close();
    _httpClient.close();
  }
}
