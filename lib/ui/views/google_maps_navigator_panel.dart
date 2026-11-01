import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../controllers/audio_mutex_controller.dart';
import '../../services/google_maps_audio_bridge.dart';

/// GoogleMapsNavigatorPanel
///
/// Embedded Google Maps WebView panel that sits alongside the Safety HUD.
/// Features:
///   • URL / share-link paste bar — accepts any google.com/maps URL or place link.
///   • Automatically converts a short-form share link to a full embed URL.
///   • Injects a JavaScript audio-event listener that fires [GoogleMapsAudioBridge]
///     to mute OrbisNav HUD TTS whenever Maps navigation voice is speaking.
///   • Dark-themed card that matches the OrbisNav HUD aesthetic.
class GoogleMapsNavigatorPanel extends StatefulWidget {
  const GoogleMapsNavigatorPanel({super.key});

  @override
  State<GoogleMapsNavigatorPanel> createState() =>
      _GoogleMapsNavigatorPanelState();
}

class _GoogleMapsNavigatorPanelState extends State<GoogleMapsNavigatorPanel> {
  late final WebViewController _webViewController;
  final TextEditingController _urlController = TextEditingController();

  // Default: embed Google Maps centred on user's region (no route)
  static const String _defaultEmbedUrl =
      'https://www.google.com/maps?output=embed';

  bool _webViewReady = false;
  bool _mapsVoiceActive = false;
  bool _isNavigating = false;
  String _statusLabel = 'Paste a Google Maps URL above';

  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;

  StreamSubscription<bool>? _mapsVoiceSub;
  StreamSubscription<bool>? _navStateSub;
  StreamSubscription<String>? _deepLinkSub;

  @override
  void initState() {
    super.initState();

    _initLocation();

    // Listen to Maps voice state changes to update the indicator
    _mapsVoiceSub = GoogleMapsAudioBridge().mapsVoiceStream.listen((active) {
      if (mounted) {
        setState(() {
          _mapsVoiceActive = active;
          _statusLabel = active
              ? 'Maps voice active — HUD muted'
              : (_isNavigating
                  ? 'Navigating to ${GoogleMapsAudioBridge().currentDestination ?? "destination"}'
                  : 'Maps ready');
        });
      }
    });

    // Listen to navigation state changes
    _navStateSub =
        GoogleMapsAudioBridge().navigationStateStream.listen((navigating) {
      if (mounted) {
        setState(() {
          _isNavigating = navigating;
          if (navigating &&
              GoogleMapsAudioBridge().currentDestination != null) {
            _statusLabel =
                'Navigating to ${GoogleMapsAudioBridge().currentDestination}';
          }
        });
      }
    });

    // Handle deep links and shared Google Maps links from Android Intent
    const channel = MethodChannel('com.orbisnav.orbisnav/audio_mutex');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onMapsUrlReceived') {
        final url = call.arguments as String?;
        if (url != null) {
          GoogleMapsAudioBridge().handleIncomingMapsUrl(url);
        }
      }
    });
    channel.invokeMethod<String>('getInitialMapsUrl').then((url) {
      if (url != null && url.isNotEmpty) {
        GoogleMapsAudioBridge().handleIncomingMapsUrl(url);
      }
    }).catchError((_) {});

    _deepLinkSub = GoogleMapsAudioBridge().deepLinkStream.listen((url) {
      if (mounted) {
        _urlController.text = url;
        // Automatically start walking navigation when a location link is opened
        _startNavigation(customDestination: url);
      }
    });

    if (GoogleMapsAudioBridge().lastIncomingUrl != null) {
      final initial = GoogleMapsAudioBridge().lastIncomingUrl!;
      _urlController.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startNavigation(customDestination: initial);
      });
    }

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0E17))
      // JavaScript channel: Maps page calls OrbisNavBridge.postMessage('speaking') /
      //                      OrbisNavBridge.postMessage('silent') to signal voice state.
      ..addJavaScriptChannel(
        'OrbisNavBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          final payload = msg.message.trim();
          final lower = payload.toLowerCase();
          if (lower == 'speaking') {
            GoogleMapsAudioBridge().setMapsVoiceActive(true);
          } else if (lower == 'silent') {
            GoogleMapsAudioBridge().setMapsVoiceActive(false);
          } else if (payload.startsWith('instruction:')) {
            final inst = payload.substring('instruction:'.length).trim();
            GoogleMapsAudioBridge().setLastInstruction(inst);
            // Announce turn instruction with priority: mutes HUD during speech, resumes HUD after
            GoogleMapsAudioBridge().setMapsVoiceActive(true);
            AudioMutexController().speak(
              text: inst,
              priority: AudioPriority.level1Safety,
              force: true,
            ).then((_) {
              GoogleMapsAudioBridge().setMapsVoiceActive(false);
            });
          } else if (payload == 'map_clicked') {
            HapticFeedback.selectionClick();
          }
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) {
          final url = request.url;
          if (url.startsWith('intent:')) {
            final match =
                RegExp(r'browser_fallback_url=([^;]+)').firstMatch(url);
            if (match != null) {
              final fallback = Uri.decodeComponent(match.group(1)!);
              _webViewController.loadRequest(Uri.parse(fallback));
            }
            return NavigationDecision.prevent;
          }
          if (!url.startsWith('http://') && !url.startsWith('https://')) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (_) {
          if (mounted) setState(() => _webViewReady = false);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _webViewReady = true);
          // Inject audio-event listener so the bridge knows when Maps TTS fires.
          // We listen to the SpeechSynthesis API and MediaElement play/pause events.
          _injectAudioBridgeScript();
        },
        onWebResourceError: (err) {
          if (err.description.contains('ERR_UNKNOWN_URL_SCHEME')) return;
          if (mounted) {
            setState(() => _statusLabel = 'Page error: ${err.description}');
          }
        },
      ))
      ..loadHtmlString(
        _buildIframeHtml(_defaultEmbedUrl),
        baseUrl: 'https://www.google.com',
      );

    if (_webViewController.platform is AndroidWebViewController) {
      (_webViewController.platform as AndroidWebViewController)
          .setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          return const GeolocationPermissionsResponse(
            allow: true,
            retain: true,
          );
        },
      );
    }
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      if (mounted) {
        setState(() => _currentPosition = pos);
        _resolveAndPublishAddress(pos.latitude, pos.longitude);
      }

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((pos) {
        if (mounted) {
          final oldPos = _currentPosition;
          _currentPosition = pos;
          if (oldPos == null ||
              Geolocator.distanceBetween(
                    oldPos.latitude,
                    oldPos.longitude,
                    pos.latitude,
                    pos.longitude,
                  ) >
                  15) {
            _resolveAndPublishAddress(pos.latitude, pos.longitude);
          }
        }
      });
    } catch (_) {}
  }

  /// Resolves the precise street and locality address using native geocoding with Nominatim fallback.
  Future<void> _resolveAndPublishAddress(double lat, double lng) async {
    try {
      final geocoding = Geocoding();
      final placemarks = await geocoding.placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if (p.name != null && p.name!.isNotEmpty && p.name != p.street) {
          parts.add(p.name!);
        }
        if (p.street != null && p.street!.isNotEmpty) {
          parts.add(p.street!);
        }
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          parts.add(p.subLocality!);
        }
        if (p.locality != null && p.locality!.isNotEmpty) {
          parts.add(p.locality!);
        }
        if (p.postalCode != null && p.postalCode!.isNotEmpty) {
          parts.add(p.postalCode!);
        }
        final formatted = parts.where((s) => s.trim().isNotEmpty).join(', ');
        if (formatted.isNotEmpty) {
          GoogleMapsAudioBridge().setCurrentAddress(formatted);
          return;
        }
      }
    } catch (_) {}

    // Fallback: Query OpenStreetMap Nominatim reverse geocoder
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng');
      final res = await http.get(url, headers: {
        'User-Agent': 'OrbisNav-BlindAssist/1.0 (contact@orbisnav.app)'
      }).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['display_name'] != null) {
          final dName = data['display_name'].toString();
          GoogleMapsAudioBridge().setCurrentAddress(dName);
        }
      }
    } catch (_) {}
  }

  /// Injects a small JS shim that proxies the browser's SpeechSynthesis API
  /// and HTMLMediaElement events to the OrbisNavBridge channel.
  Future<void> _injectAudioBridgeScript() async {
    const script = r"""
(function() {
  // Guard: only inject once
  if (window.__orbisnavBridgeInjected) return;
  window.__orbisnavBridgeInjected = true;

  function notifySpeaking(active) {
    try {
      OrbisNavBridge.postMessage(active ? 'speaking' : 'silent');
    } catch(e) {}
  }

  // 1. Hook SpeechSynthesis if available
  if ('speechSynthesis' in window && window.speechSynthesis) {
    try {
      var origSpeak = window.speechSynthesis.speak.bind(window.speechSynthesis);
      window.speechSynthesis.speak = function(utt) {
        notifySpeaking(true);
        if (utt && utt.text) {
          try { OrbisNavBridge.postMessage('instruction:' + utt.text); } catch(e) {}
        }
        utt.addEventListener('end', function() { notifySpeaking(false); });
        utt.addEventListener('error', function() { notifySpeaking(false); });
        origSpeak(utt);
      };
    } catch(e) {}
  }

  // 2. Hook all <audio> / <video> elements that Google Maps creates
  var origPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function() {
    notifySpeaking(true);
    this.addEventListener('ended', function() { notifySpeaking(false); }, { once: true });
    this.addEventListener('pause', function() { notifySpeaking(false); }, { once: true });
    return origPlay.apply(this, arguments);
  };

  // 3. MutationObserver to catch dynamically injected audio elements
  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(m) {
      m.addedNodes.forEach(function(node) {
        if (node.nodeName === 'AUDIO' || node.nodeName === 'VIDEO') {
          node.addEventListener('play', function() { notifySpeaking(true); });
          node.addEventListener('ended', function() { notifySpeaking(false); });
          node.addEventListener('pause', function() { notifySpeaking(false); });
        }
      });
    });
  });
  observer.observe(document.body || document.documentElement,
    { childList: true, subtree: true });

  // 4. Blind-Assist Real-Time Step Extractor:
  // Scans Google Maps DOM for active turn directions and broadcasts them to OrbisNavBridge
  var lastExtractedStep = '';
  setInterval(function() {
    try {
      var candidateSelectors = [
        '.directions-mode-step-summary',
        '.section-directions-trip-description',
        '.transit-mode-step',
        '[class*="directions-step"]',
        '[class*="step-text"]',
        '[aria-label*="turn"]',
        '[aria-label*="head"]',
        '[aria-label*="continue"]'
      ];
      for (var i = 0; i < candidateSelectors.length; i++) {
        var el = document.querySelector(candidateSelectors[i]);
        if (el && el.innerText) {
          var txt = el.innerText.trim();
          if (txt.length > 3 && txt !== lastExtractedStep) {
            lastExtractedStep = txt;
            OrbisNavBridge.postMessage('instruction:' + txt);
            break;
          }
        }
      }
    } catch(e) {}
  }, 2500);
})();
""";
    try {
      await _webViewController.runJavaScript(script);
    } catch (_) {}
  }

  /// Extracts the destination name or coordinates from raw input.
  String _extractDestination(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) return 'Destination';

    if (raw.startsWith('{') && raw.endsWith('}')) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map) {
          if (parsed['location'] != null) return parsed['location'].toString();
          if (parsed['latitude'] != null && parsed['longitude'] != null) {
            return '${parsed['latitude']}, ${parsed['longitude']}';
          }
        }
      } catch (_) {}
    }

    if (raw.startsWith('geo:')) {
      final without = raw.substring(4);
      final qIdx = without.indexOf('q=');
      if (qIdx != -1) {
        return Uri.decodeComponent(without.substring(qIdx + 2));
      }
      return without.split('?').first.trim();
    }

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final uri = Uri.tryParse(raw);
      if (uri != null) {
        if (uri.queryParameters.containsKey('daddr')) {
          return uri.queryParameters['daddr']!;
        }
        if (uri.queryParameters.containsKey('destination')) {
          return uri.queryParameters['destination']!;
        }
        final segs = uri.pathSegments;
        final dirIdx = segs.indexOf('dir');
        if (dirIdx != -1 && dirIdx + 1 < segs.length) {
          return Uri.decodeComponent(segs.last).replaceAll('+', ' ');
        }
        final placeIdx = segs.indexOf('place');
        if (placeIdx != -1 && placeIdx + 1 < segs.length) {
          return Uri.decodeComponent(segs[placeIdx + 1]).replaceAll('+', ' ');
        }
        if (uri.queryParameters.containsKey('q')) {
          return uri.queryParameters['q']!;
        }
      }
    }

    return raw;
  }

  /// Builds walking directions URL ensuring origin is ALWAYS the user's current GPS location.
  String _buildWalkingNavigationUrl(String rawDestination,
      {Position? position}) {
    final dest = _extractDestination(rawDestination);
    final encoded = Uri.encodeComponent(dest);
    final pos = position ?? _currentPosition;
    final origin = (pos != null)
        ? '${pos.latitude},${pos.longitude}'
        : 'Current+Location';
    return 'https://maps.google.com/maps?saddr=$origin&daddr=$encoded&dirflg=w&output=embed';
  }

  /// Resolves any pasted Maps URL, query, or coordinate object to an embeddable form.
  /// Enforces that the starting point is always the user's current GPS location.
  String _resolveEmbedUrl(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) {
      if (_currentPosition != null) {
        return 'https://maps.google.com/maps?q=${_currentPosition!.latitude},${_currentPosition!.longitude}&output=embed';
      }
      return _defaultEmbedUrl;
    }

    final dest = _extractDestination(raw);
    return _buildWalkingNavigationUrl(dest);
  }

  String _buildIframeHtml(String embedUrl) {
    return '''<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%;
      height: 100%;
      overflow: hidden;
      background-color: #0A0E17;
      touch-action: manipulation;
    }
    iframe {
      border: 0;
      width: 100%;
      height: 100%;
      display: block;
    }
  </style>
</head>
<body>
  <iframe
    id="maps_frame"
    src="$embedUrl"
    allow="geolocation *; autoplay *; camera *"
    allowfullscreen>
  </iframe>
  <script>
    window.addEventListener('click', function() {
      try { OrbisNavBridge.postMessage('map_clicked'); } catch(e) {}
    });
  </script>
</body>
</html>''';
  }

  void _loadUrl() {
    final embed = _resolveEmbedUrl(_urlController.text);
    _webViewController.loadHtmlString(
      _buildIframeHtml(embed),
      baseUrl: 'https://www.google.com',
    );
    FocusScope.of(context).unfocus();
    setState(() => _statusLabel = 'Loading…');
  }

  void _toggleNavigation() {
    if (_isNavigating) {
      _stopNavigation();
    } else {
      _startNavigation();
    }
  }

  void _startNavigation({String? customDestination}) {
    final raw = (customDestination ?? _urlController.text).trim();
    if (raw.isEmpty) {
      AudioMutexController().speak(
        text: 'Please enter, paste, or select a destination first.',
        priority: AudioPriority.level2Navigation,
        force: true,
      );
      return;
    }

    final destName = _extractDestination(raw);
    final navUrl = _buildWalkingNavigationUrl(raw);

    setState(() {
      _isNavigating = true;
      _statusLabel = 'Navigating to $destName';
    });

    GoogleMapsAudioBridge().setNavigating(true, destination: destName);

    _webViewController.loadHtmlString(
      _buildIframeHtml(navUrl),
      baseUrl: 'https://www.google.com',
    );

    FocusScope.of(context).unfocus();
    HapticFeedback.heavyImpact();

    // Destination guidance announced aloud in the beginning:
    AudioMutexController().speak(
      text:
          'Starting walking navigation to $destName from your current location. Turn directions have first priority. Safety hazard HUD will be muted while directions are spoken, then will resume.',
      priority: AudioPriority.level1Safety,
      force: true,
    );

    // Initial direction cue
    Future.delayed(const Duration(milliseconds: 3800), () {
      if (mounted && _isNavigating) {
        AudioMutexController().speak(
          text:
              'Head forward along your walking route towards $destName. The map is tracking in real time.',
          priority: AudioPriority.level2Navigation,
        );
      }
    });
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _statusLabel = 'Navigation ended';
    });

    GoogleMapsAudioBridge().setNavigating(false);

    HapticFeedback.mediumImpact();

    AudioMutexController().speak(
      text: 'Walking navigation ended. General obstacle detection active.',
      priority: AudioPriority.level2Navigation,
      force: true,
    );
  }

  void _repeatInstruction() {
    final last = GoogleMapsAudioBridge().lastInstruction;
    if (last != null && last.isNotEmpty) {
      AudioMutexController().speak(
        text: 'Next turn: $last',
        priority: AudioPriority.level1Safety,
        force: true,
      );
    } else {
      final dest =
          GoogleMapsAudioBridge().currentDestination ?? 'your destination';
      AudioMutexController().speak(
        text: 'Navigating to $dest. Continue along current walking route.',
        priority: AudioPriority.level2Navigation,
        force: true,
      );
    }
    HapticFeedback.selectionClick();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapsVoiceSub?.cancel();
    _navStateSub?.cancel();
    _deepLinkSub?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentCyan = Color(0xFF00E5FF);
    const bgDark = Color(0xFF0D1626);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bgDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _mapsVoiceActive
              ? const Color(0xFF76FF03).withValues(alpha: 0.8)
              : accentCyan.withValues(alpha: 0.35),
          width: _mapsVoiceActive ? 2.0 : 1.2,
        ),
        boxShadow: _mapsVoiceActive
            ? [
                BoxShadow(
                  color: const Color(0xFF76FF03).withValues(alpha: 0.18),
                  blurRadius: 12,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 16,
                  color: _mapsVoiceActive
                      ? const Color(0xFF76FF03)
                      : accentCyan,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'GOOGLE MAPS NAVIGATOR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: _mapsVoiceActive
                          ? const Color(0xFF76FF03)
                          : accentCyan,
                    ),
                  ),
                ),
                // Voice-active pill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_mapsVoiceActive || _isNavigating)
                        ? const Color(0xFF76FF03).withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (_mapsVoiceActive || _isNavigating)
                          ? const Color(0xFF76FF03)
                          : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_mapsVoiceActive || _isNavigating)
                              ? const Color(0xFF76FF03)
                              : Colors.white30,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _mapsVoiceActive
                            ? 'HUD MUTED'
                            : (_isNavigating ? 'NAVIGATING' : 'MAPS READY'),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: (_mapsVoiceActive || _isNavigating)
                              ? const Color(0xFF76FF03)
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── URL Paste search bar ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141F30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: accentCyan.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        const Icon(Icons.search,
                            size: 16, color: Colors.white38),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            decoration: const InputDecoration(
                              hintText:
                                  'Paste Google Maps URL or search query…',
                              hintStyle: TextStyle(
                                  color: Colors.white38, fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => _loadUrl(),
                            textInputAction: TextInputAction.go,
                          ),
                        ),
                        // Paste from clipboard shortcut
                        GestureDetector(
                          onTap: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              _urlController.text = data!.text!;
                              _loadUrl();
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.content_paste,
                                size: 15, color: Colors.white38),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // GO button
                Semantics(
                  button: true,
                  label: 'Load map',
                  child: GestureDetector(
                    onTap: _loadUrl,
                    child: Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: accentCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: accentCyan.withValues(alpha: 0.5)),
                      ),
                      child: const Icon(Icons.arrow_forward,
                          size: 18, color: accentCyan),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Status hint & Precise Current Address ───────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (GoogleMapsAudioBridge().currentAddress != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.my_location,
                          size: 14,
                          color: Color(0xFF00E5FF),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Current: ${GoogleMapsAudioBridge().currentAddress!}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF00E5FF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  _statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: (_mapsVoiceActive || _isNavigating)
                        ? const Color(0xFF76FF03)
                        : Colors.white38,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          // ── Blind-Friendly Navigation Controls ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Primary Action: START / STOP WALKING NAVIGATION
                Semantics(
                  button: true,
                  label: _isNavigating
                      ? 'Stop Walking Navigation'
                      : 'Start Walking Navigation',
                  hint: _isNavigating
                      ? 'Double tap to stop walking navigation and return to general safety monitoring'
                      : 'Double tap to begin voice-guided turn-by-turn walking navigation to your destination. Navigation speech has first priority over HUD speech.',
                  child: InkWell(
                    onTap: _toggleNavigation,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 54, // Meets TalkBack 48x48 touch target requirement
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _isNavigating
                            ? const Color(0xFFD32F2F)
                            : const Color(0xFF00E5FF),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: (_isNavigating
                                    ? const Color(0xFFD32F2F)
                                    : const Color(0xFF00E5FF))
                                .withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isNavigating
                                ? Icons.stop_circle_outlined
                                : Icons.directions_walk,
                            color: _isNavigating ? Colors.white : Colors.black,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isNavigating
                                ? 'STOP WALKING NAVIGATION'
                                : 'START WALKING NAVIGATION',
                            style: TextStyle(
                              color: _isNavigating ? Colors.white : Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // If navigating: show "REPEAT NEXT TURN GUIDANCE" button
                if (_isNavigating) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: 'Repeat Next Turn Instruction',
                    hint:
                        'Double tap to hear the latest walking navigation direction spoken aloud',
                    child: InkWell(
                      onTap: _repeatInstruction,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14243B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                const Color(0xFF76FF03).withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.volume_up,
                              color: Color(0xFF76FF03),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'REPEAT NEXT TURN GUIDANCE',
                              style: TextStyle(
                                color: Color(0xFF76FF03),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── WebView ───────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: SizedBox(
              height: 340,
              child: Stack(
                children: [
                  WebViewWidget(
                    controller: _webViewController,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
                  if (!_webViewReady)
                    Container(
                      color: const Color(0xFF0D1626),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: Color(0xFF00E5FF),
                              strokeWidth: 2,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Loading Google Maps…',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
