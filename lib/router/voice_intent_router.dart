import '../models/voice_requirement_models.dart';

/// Intent Rule Definition for the On-Device Lightweight NLP Classifier.
class _SubsystemIntentRule {
  final VoiceSubsystem subsystem;
  final String intentType;
  final List<RegExp> regexPatterns;
  final List<String> keywordTokens;
  final double confidenceWeight;

  const _SubsystemIntentRule({
    required this.subsystem,
    required this.intentType,
    required this.regexPatterns,
    required this.keywordTokens,
    this.confidenceWeight = 0.95,
  });
}

/// On-Device Voice Requirement Intent Router.
///
/// Features:
/// - Sub-50ms execution latency (deterministic regex + keyword tokenizer).
/// - 100% offline capability (no network round-trip for intent routing).
/// - Comprehensive coverage of BVI conversational expressions.
/// - Parameter extraction for object queries, currency types, and document types.
/// - Seamless fallback to [VoiceSubsystem.sceneQa] for complex multimodal questions.
class VoiceIntentRouter {
  static final VoiceIntentRouter _instance = VoiceIntentRouter._internal();
  factory VoiceIntentRouter() => _instance;

  VoiceIntentRouter._internal() {
    _compileIntentRules();
  }

  late final List<_SubsystemIntentRule> _rules;

  void _compileIntentRules() {
    _rules = [
      // 1. SHORT_TEXT_ENGINE
      _SubsystemIntentRule(
        subsystem: VoiceSubsystem.shortText,
        intentType: "INTENT: SHORT_TEXT",
        regexPatterns: [
          RegExp(r'\b(read\s*(this\s*)?(short\s*)?(text|sign|label|words?|board|writing|tag|package|box))\b', caseSensitive: false),
          RegExp(r'\b(what\s*(does\s*this|does\s*it)\s*say)\b', caseSensitive: false),
          RegExp(r'\b(what\s*is\s*written(\s*(here|on\s*this|on\s*it))?)\b', caseSensitive: false),
          RegExp(r'\b(short\s*text|read\s*sign|read\s*it|read\s*writing)\b', caseSensitive: false),
          RegExp(r'\b(instant\s*ocr|quick\s*read|read\s*aloud)\b', caseSensitive: false),
        ],
        keywordTokens: ['read', 'sign', 'label', 'words', 'short text', 'writing', 'say', 'written'],
        confidenceWeight: 0.98,
      ),

      // 2. DOCUMENT_ENGINE
      _SubsystemIntentRule(
        subsystem: VoiceSubsystem.document,
        intentType: "INTENT: DOCUMENT",
        regexPatterns: [
          RegExp(r'\b(scan\s*(this\s*)?(document|letter|bill|page|receipt|paper|book|form|invoice|contract))\b', caseSensitive: false),
          RegExp(r'\b(read\s*(this\s*)?(document|letter|bill|receipt|page|paper|book|invoice|mail))\b', caseSensitive: false),
          RegExp(r'\b(document\s*(scanner|scan|mode)|batch\s*ocr|read\s*whole\s*page)\b', caseSensitive: false),
          RegExp(r'\b(align\s*(page|corners?|document)|frame\s*(page|document))\b', caseSensitive: false),
        ],
        keywordTokens: ['document', 'letter', 'bill', 'receipt', 'page', 'scan document', 'invoice'],
        confidenceWeight: 0.96,
      ),

      // 3. BARCODE_ENGINE
      _SubsystemIntentRule(
        subsystem: VoiceSubsystem.barcode,
        intentType: "INTENT: BARCODE",
        regexPatterns: [
          RegExp(r'\b(scan\s*(this\s*)?(barcode|bar\s*code|qr|qr\s*code|code))\b', caseSensitive: false),
          RegExp(r'\b(check\s*(this\s*)?(barcode|product|code))\b', caseSensitive: false),
          RegExp(r'\b(what\s*product\s*(is\s*this|am\s*i\s*holding)|identify\s*product)\b', caseSensitive: false),
          RegExp(r'\b(find\s*barcode|beep\s*barcode|upc|isbn|product\s*info)\b', caseSensitive: false),
        ],
        keywordTokens: ['barcode', 'qr code', 'product', 'upc', 'isbn', 'scan barcode'],
        confidenceWeight: 0.97,
      ),

      // 4. CURRENCY & PERSON ENGINE
      _SubsystemIntentRule(
        subsystem: VoiceSubsystem.currencyPerson,
        intentType: "INTENT: CURRENCY_PERSON",
        regexPatterns: [
          RegExp(r'\b(count\s*(the\s*)?(money|cash|currency|bills?|notes?))\b', caseSensitive: false),
          RegExp(r'\b(how\s*much\s*(money|cash|currency|is\s*this\s*bill|is\s*this\s*note))\b', caseSensitive: false),
          RegExp(r'\b(identify\s*(money|currency|note|bill|rupees?|dollars?|euros?|pounds?))\b', caseSensitive: false),
          RegExp(r'\b(who\s*(is\s*in\s*front\s*(of\s*me)?|is\s*here|is\s*that|are\s*they))\b', caseSensitive: false),
          RegExp(r'\b(recognize\s*(faces?|person|people)|who\s*am\s*i\s*looking\s*at)\b', caseSensitive: false),
          RegExp(r'\b(any\s*people|is\s*anyone\s*(here|nearby))\b', caseSensitive: false),
        ],
        keywordTokens: [
          'money', 'currency', 'cash', 'rupees', 'dollars', 'bill', 'banknote',
          'who is', 'person', 'people', 'face', 'someone'
        ],
        confidenceWeight: 0.96,
      ),

      // 5. LIGHT_DETECTOR_ENGINE
      _SubsystemIntentRule(
        subsystem: VoiceSubsystem.lightDetector,
        intentType: "INTENT: LIGHT_DETECTOR",
        regexPatterns: [
          RegExp(r'\b(check\s*(the\s*)?(light\s*level|light|brightness|lux))\b', caseSensitive: false),
          RegExp(r'\b(is\s*(the\s*)?light\s*(on|off)|how\s*bright\s*is\s*it)\b', caseSensitive: false),
          RegExp(r'\b(light\s*(level|meter|detector|sensor)|measure\s*light)\b', caseSensitive: false),
          RegExp(r'\b(any\s*light\s*in\s*here|am\s*i\s*in\s*the\s*dark)\b', caseSensitive: false),
        ],
        keywordTokens: ['light', 'brightness', 'dark', 'lux', 'light level', 'is light on'],
        confidenceWeight: 0.97,
      ),

      // 6. SCENE & VISUAL QA ENGINE (Explicit Scene Prompts)
      _SubsystemIntentRule(
        subsystem: VoiceSubsystem.sceneQa,
        intentType: "INTENT: SCENE",
        regexPatterns: [
          RegExp(r'\b(describe\s*(the\s*)?(scene|room|surroundings|environment|area|view))\b', caseSensitive: false),
          RegExp(r'\b(what\s*(is\s*in\s*front\s*of\s*me|do\s*you\s*see|is\s*around\s*me|is\s*ahead))\b', caseSensitive: false),
          RegExp(r'\b(look\s*around|where\s*am\s*i|tell\s*me\s*what\s*you\s*see)\b', caseSensitive: false),
          RegExp(r'\b(where\s*(is|are)\s*(my|the)\s+([a-zA-Z0-9_\s]+))\b', caseSensitive: false),
          RegExp(r'\b(find\s*(my|the)\s+([a-zA-Z0-9_\s]+))\b', caseSensitive: false),
        ],
        keywordTokens: ['describe', 'scene', 'room', 'surroundings', 'front of me', 'find', 'where is'],
        confidenceWeight: 0.94,
      ),
    ];
  }

  /// Classifies a spoken utterance into a targeted subsystem in <50ms.
  VoiceIntentResult route(String spokenUtterance) {
    final stopwatch = Stopwatch()..start();
    final clean = spokenUtterance.trim().toLowerCase();

    if (clean.isEmpty) {
      stopwatch.stop();
      return VoiceIntentResult(
        subsystem: VoiceSubsystem.none,
        confidence: 0.0,
        rawQuery: spokenUtterance,
        cleanQuery: clean,
        intentType: "INTENT: EMPTY",
        matchedPattern: "NONE",
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 1. Direct Regex Pattern Matching (Highest Precision)
    for (final rule in _rules) {
      for (final pattern in rule.regexPatterns) {
        final match = pattern.firstMatch(clean);
        if (match != null) {
          final params = _extractParameters(rule.subsystem, clean, match);
          stopwatch.stop();
          return VoiceIntentResult(
            subsystem: rule.subsystem,
            confidence: rule.confidenceWeight,
            rawQuery: spokenUtterance,
            cleanQuery: clean,
            intentType: rule.intentType,
            matchedPattern: pattern.pattern,
            parameters: params,
            isCloudFallbackRequired: rule.subsystem == VoiceSubsystem.sceneQa,
            latencyMs: stopwatch.elapsedMilliseconds,
          );
        }
      }
    }

    // 2. Tokenized Fuzzy Keyword Scoring
    _SubsystemIntentRule? bestRule;
    double highestScore = 0.0;

    for (final rule in _rules) {
      int hits = 0;
      for (final token in rule.keywordTokens) {
        if (clean.contains(token)) {
          hits++;
        }
      }
      if (hits > 0) {
        final score = (hits / rule.keywordTokens.length) * rule.confidenceWeight;
        if (score > highestScore) {
          highestScore = score;
          bestRule = rule;
        }
      }
    }

    if (bestRule != null && highestScore >= 0.15) {
      final params = _extractParameters(bestRule.subsystem, clean, null);
      stopwatch.stop();
      return VoiceIntentResult(
        subsystem: bestRule.subsystem,
        confidence: highestScore.clamp(0.5, 0.92),
        rawQuery: spokenUtterance,
        cleanQuery: clean,
        intentType: bestRule.intentType,
        matchedPattern: "KEYWORD_TOKEN_SCORE",
        parameters: params,
        isCloudFallbackRequired: bestRule.subsystem == VoiceSubsystem.sceneQa,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 3. Fallback: Any other natural spoken question defaults to Cloud Multimodal Scene QA
    stopwatch.stop();
    return VoiceIntentResult.fallback(
      spokenUtterance,
      latencyMs: stopwatch.elapsedMilliseconds,
    );
  }

  Map<String, dynamic> _extractParameters(
    VoiceSubsystem subsystem,
    String cleanText,
    Match? match,
  ) {
    final params = <String, dynamic>{'query': cleanText};

    switch (subsystem) {
      case VoiceSubsystem.sceneQa:
        final findMatch = RegExp(r'\b(find|where\s*(is|are))\s*(my|the)?\s*([a-zA-Z0-9\s]+)', caseSensitive: false)
            .firstMatch(cleanText);
        if (findMatch != null && findMatch.groupCount >= 4) {
          final target = findMatch.group(4)?.trim();
          if (target != null && target.isNotEmpty) {
            params['targetObject'] = target;
          }
        }
        break;

      case VoiceSubsystem.currencyPerson:
        if (cleanText.contains('rupee')) params['currencyHint'] = 'INR';
        if (cleanText.contains('dollar')) params['currencyHint'] = 'USD';
        if (cleanText.contains('euro')) params['currencyHint'] = 'EUR';
        if (cleanText.contains('pound')) params['currencyHint'] = 'GBP';
        if (cleanText.contains('who') || cleanText.contains('person') || cleanText.contains('face')) {
          params['targetFocus'] = 'person';
        } else {
          params['targetFocus'] = 'currency';
        }
        break;

      case VoiceSubsystem.document:
        if (cleanText.contains('bill')) params['documentType'] = 'bill';
        if (cleanText.contains('receipt')) params['documentType'] = 'receipt';
        if (cleanText.contains('letter')) params['documentType'] = 'letter';
        break;

      default:
        break;
    }

    return params;
  }
}
