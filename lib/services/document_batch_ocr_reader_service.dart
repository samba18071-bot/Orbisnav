import 'dart:async';
import 'package:flutter/services.dart';
import '../controllers/audio_mutex_controller.dart';

/// Playback status of the document reader.
enum ReaderPlaybackStatus {
  idle,
  playing,
  paused,
  completed,
}

/// A parsed, structured paragraph from scanned document OCR.
class ParsedDocumentParagraph {
  final int index;
  final int pageNumber;
  final String text;
  final bool isHeading;
  final int wordCount;

  const ParsedDocumentParagraph({
    required this.index,
    required this.pageNumber,
    required this.text,
    this.isHeading = false,
    required this.wordCount,
  });
}

/// Session containing multiple pages and paragraphs with navigation state.
class DocumentReadingSession {
  final List<ParsedDocumentParagraph> paragraphs;
  final int currentParagraphIndex;
  final int totalPages;
  final ReaderPlaybackStatus status;
  final double playbackSpeed;

  const DocumentReadingSession({
    required this.paragraphs,
    required this.currentParagraphIndex,
    required this.totalPages,
    required this.status,
    required this.playbackSpeed,
  });

  factory DocumentReadingSession.empty() {
    return const DocumentReadingSession(
      paragraphs: [],
      currentParagraphIndex: 0,
      totalPages: 0,
      status: ReaderPlaybackStatus.idle,
      playbackSpeed: 1.0,
    );
  }

  ParsedDocumentParagraph? get currentParagraph {
    if (paragraphs.isEmpty || currentParagraphIndex < 0 || currentParagraphIndex >= paragraphs.length) {
      return null;
    }
    return paragraphs[currentParagraphIndex];
  }

  int get totalParagraphs => paragraphs.length;
  bool get hasContent => paragraphs.isNotEmpty;
  bool get isPlaying => status == ReaderPlaybackStatus.playing;
  bool get isPaused => status == ReaderPlaybackStatus.paused;
}

/// Service managing structured batch OCR document reading, paragraph controls & audio playback.
class DocumentBatchOcrReaderService {
  final AudioMutexController _audioMutex;

  final StreamController<DocumentReadingSession> _sessionStreamController =
      StreamController<DocumentReadingSession>.broadcast();

  Stream<DocumentReadingSession> get sessionStream => _sessionStreamController.stream;

  final List<ParsedDocumentParagraph> _paragraphs = [];
  int _currentPageCount = 0;
  int _currentIndex = 0;
  ReaderPlaybackStatus _status = ReaderPlaybackStatus.idle;
  double _playbackSpeed = 1.0;
  Timer? _playbackTimer;

  DocumentBatchOcrReaderService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  DocumentReadingSession get currentSession => DocumentReadingSession(
        paragraphs: List.unmodifiable(_paragraphs),
        currentParagraphIndex: _currentIndex,
        totalPages: _currentPageCount,
        status: _status,
        playbackSpeed: _playbackSpeed,
      );

  /// Ingests a new page of raw OCR text and formats it into natural paragraphs.
  DocumentReadingSession addPage(String rawOcrText) {
    _currentPageCount++;
    final newParagraphs = _parseRawOcrToParagraphs(rawOcrText, _currentPageCount, _paragraphs.length);
    _paragraphs.addAll(newParagraphs);

    final session = currentSession;
    _sessionStreamController.add(session);

    _audioMutex.speak(
      text: 'Page $_currentPageCount added. ${_paragraphs.length} paragraphs ready.',
      priority: AudioPriority.level2Navigation,
      channelIndex: 2,
      haptic: true,
    );

    return session;
  }

  /// Clears the current reading document session.
  void clearDocument() {
    stopReading();
    _paragraphs.clear();
    _currentPageCount = 0;
    _currentIndex = 0;
    _status = ReaderPlaybackStatus.idle;

    final session = DocumentReadingSession.empty();
    _sessionStreamController.add(session);
  }

  /// Starts or resumes reading from the current paragraph.
  void startReading({int? startFrom}) {
    if (_paragraphs.isEmpty) return;

    if (startFrom != null && startFrom >= 0 && startFrom < _paragraphs.length) {
      _currentIndex = startFrom;
    }

    _status = ReaderPlaybackStatus.playing;
    _readCurrentParagraph();
  }

  /// Pauses current reading.
  void pauseReading() {
    if (_status != ReaderPlaybackStatus.playing) return;
    _status = ReaderPlaybackStatus.paused;
    _playbackTimer?.cancel();

    _audioMutex.speak(
      text: 'Reading paused.',
      priority: AudioPriority.level2Navigation,
      channelIndex: 2,
      haptic: false,
    );

    _sessionStreamController.add(currentSession);
  }

  /// Resumes reading after pause.
  void resumeReading() {
    if (_status == ReaderPlaybackStatus.paused) {
      startReading();
    }
  }

  /// Stops reading completely and resets index to the beginning.
  void stopReading() {
    _playbackTimer?.cancel();
    _status = ReaderPlaybackStatus.idle;
    _currentIndex = 0;
    _sessionStreamController.add(currentSession);
  }

  /// Navigates to the next paragraph.
  void nextParagraph() {
    if (_paragraphs.isEmpty) return;
    if (_currentIndex + 1 < _paragraphs.length) {
      _currentIndex++;
      _triggerParagraphTransitionHaptic();
      if (_status == ReaderPlaybackStatus.playing) {
        _readCurrentParagraph();
      } else {
        _sessionStreamController.add(currentSession);
      }
    } else {
      _status = ReaderPlaybackStatus.completed;
      _audioMutex.speak(
        text: 'End of document.',
        priority: AudioPriority.level2Navigation,
        channelIndex: 2,
        haptic: true,
      );
      _sessionStreamController.add(currentSession);
    }
  }

  /// Navigates to the previous paragraph.
  void previousParagraph() {
    if (_paragraphs.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      _triggerParagraphTransitionHaptic();
      if (_status == ReaderPlaybackStatus.playing) {
        _readCurrentParagraph();
      } else {
        _sessionStreamController.add(currentSession);
      }
    }
  }

  /// Sets TTS speed (0.8x, 1.0x, 1.25x, 1.5x, 2.0x).
  void setPlaybackSpeed(double speed) {
    if (speed >= 0.5 && speed <= 3.0) {
      _playbackSpeed = speed;
      _sessionStreamController.add(currentSession);
    }
  }

  void _readCurrentParagraph() {
    _playbackTimer?.cancel();
    if (_currentIndex < 0 || _currentIndex >= _paragraphs.length) {
      _status = ReaderPlaybackStatus.completed;
      _sessionStreamController.add(currentSession);
      return;
    }

    final p = _paragraphs[_currentIndex];
    _sessionStreamController.add(currentSession);

    // Speak the paragraph text through Audio Mutex
    _audioMutex.speak(
      text: p.text,
      priority: AudioPriority.level2Navigation,
      channelIndex: 2,
      haptic: false,
    );

    // Calculate approximate duration based on word count and playback speed
    // Average speaking speed: ~150 words per minute -> ~400ms per word
    final wordDurationMs = (400 / _playbackSpeed).round();
    final totalDurationMs = (p.wordCount * wordDurationMs).clamp(1800, 45000);

    _playbackTimer = Timer(Duration(milliseconds: totalDurationMs), () {
      if (_status == ReaderPlaybackStatus.playing) {
        nextParagraph();
      }
    });
  }

  List<ParsedDocumentParagraph> _parseRawOcrToParagraphs(String raw, int pageNum, int startIndex) {
    final clean = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawBlocks = clean.split(RegExp(r'\n\s*\n+'));
    final List<ParsedDocumentParagraph> result = [];

    int currIndex = startIndex;
    for (final block in rawBlocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      // Filter out tiny single-character noise
      if (trimmed.length <= 2 && !RegExp(r'[a-zA-Z0-9]').hasMatch(trimmed)) {
        continue;
      }

      final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final isHeading = words.length <= 6 && (trimmed.endsWith(':') || trimmed.toUpperCase() == trimmed);

      result.add(
        ParsedDocumentParagraph(
          index: currIndex++,
          pageNumber: pageNum,
          text: trimmed,
          isHeading: isHeading,
          wordCount: words.length,
        ),
      );
    }

    // Fallback: If no paragraph splits were detected, split by sentences
    if (result.isEmpty && clean.trim().isNotEmpty) {
      final sentences = clean.split(RegExp(r'(?<=[.?!])\s+'));
      for (final s in sentences) {
        final t = s.trim();
        if (t.isNotEmpty) {
          final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
          result.add(
            ParsedDocumentParagraph(
              index: currIndex++,
              pageNumber: pageNum,
              text: t,
              isHeading: false,
              wordCount: words.length,
            ),
          );
        }
      }
    }

    return result;
  }

  Future<void> _triggerParagraphTransitionHaptic() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  void dispose() {
    _playbackTimer?.cancel();
    _sessionStreamController.close();
  }
}
