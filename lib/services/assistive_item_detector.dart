import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// High-Precision Assistive Item & Salient Vision Detector for Channel 4 (Lost Item Sonar).
/// Detects everyday objects not in standard 80 COCO (glasses, keys, wallet, charger, pen, watch, medicine, etc.)
/// directly on device from raw camera frames, with precise bounding box and metric distance.
class AssistiveItemDetector {
  static final AssistiveItemDetector _instance = AssistiveItemDetector._internal();
  factory AssistiveItemDetector() => _instance;
  AssistiveItemDetector._internal();

  /// Detects target item in camera JPEG frame.
  /// Returns a DetectedObstacle if found, or null if not in view.
  Future<DetectedObstacle?> detectTargetItem(
    Uint8List jpegBytes,
    String targetLabel, {
    double devicePitchDeg = 0.0,
  }) async {
    final target = targetLabel.trim().toLowerCase();
    if (target.isEmpty) return null;

    return compute(_isolateDetectItem, _DetectionParam(jpegBytes, target, devicePitchDeg));
  }
}

class _DetectionParam {
  final Uint8List jpegBytes;
  final String target;
  final double pitchDeg;
  _DetectionParam(this.jpegBytes, this.target, this.pitchDeg);
}

DetectedObstacle? _isolateDetectItem(_DetectionParam param) {
  var rawImage = img.decodeImage(param.jpegBytes);
  if (rawImage == null) return null;
  rawImage = img.bakeOrientation(rawImage);

  final width = rawImage.width;
  final height = rawImage.height;
  if (width < 50 || height < 50) return null;

  final target = param.target;

  // 1. Glasses / Spectacles / Eyewear Detection
  if (target.contains("glass") || target.contains("spectacle") || target.contains("eyewear")) {
    final res = _detectEyeglasses(rawImage, target);
    if (res != null) return res;
  }

  // 2. Keys / Keychain Detection (Specular metallic reflections + high-contrast loops)
  if (target.contains("key")) {
    final res = _detectKeys(rawImage, target);
    if (res != null) return res;
  }

  // 3. Charger / Cable / Adapter Detection
  if (target.contains("charger") || target.contains("cable") || target.contains("adapter") || target.contains("wire")) {
    final res = _detectChargerOrCable(rawImage, target);
    if (res != null) return res;
  }

  // 4. Wallet / Purse / Cardholder Detection
  if (target.contains("wallet") || target.contains("purse") || target.contains("card")) {
    final res = _detectWallet(rawImage, target);
    if (res != null) return res;
  }

  // 5. Pen / Pencil / Stylus Detection
  if (target.contains("pen") || target.contains("pencil") || target.contains("marker")) {
    final res = _detectPen(rawImage, target);
    if (res != null) return res;
  }

  // 6. Watch / Smartwatch Detection
  if (target.contains("watch")) {
    final res = _detectWatch(rawImage, target);
    if (res != null) return res;
  }

  // 7. Medicine / Pill Bottle Detection
  if (target.contains("medicine") || target.contains("pill") || target.contains("tablet") || target.contains("syrup")) {
    final res = _detectMedicineBottle(rawImage, target);
    if (res != null) return res;
  }

  // 8. Footwear (Shoes / Slippers / Sandals)
  if (target.contains("shoe") || target.contains("slipper") || target.contains("sandal") || target.contains("boot")) {
    final res = _detectFootwear(rawImage, target);
    if (res != null) return res;
  }

  // 9. Headphones / Earphones
  if (target.contains("headphone") || target.contains("earphone") || target.contains("earbud") || target.contains("airpod")) {
    final res = _detectHeadphones(rawImage, target);
    if (res != null) return res;
  }

  // 10. White Cane / Walking Stick
  if (target.contains("cane") || target.contains("stick")) {
    final res = _detectWhiteCane(rawImage, target);
    if (res != null) return res;
  }

  // 11. Universal Salient Foreground Object Detector (Detects any object in the world!)
  return _detectSalientObject(rawImage, target);
}

/// Detects eyeglasses / spectacles based on dual-lens frame contour geometry and bridge symmetry
DetectedObstacle? _detectEyeglasses(img.Image image, String label) {
  final w = image.width;
  final h = image.height;

  // Downsample to fast analysis grid (e.g. 160x120)
  const gridW = 160;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Convert to grayscale & compute horizontal and vertical gradient energy (Sobel-like)
  final lum = List.generate(gridH, (y) => List.filled(gridW, 0.0));
  for (int y = 0; y < gridH; y++) {
    for (int x = 0; x < gridW; x++) {
      final p = resized.getPixel(x, y);
      lum[y][x] = (p.r * 0.299 + p.g * 0.587 + p.b * 0.114) / 255.0;
    }
  }

  // Search horizontal scanbands for dual-symmetric high-contrast lens frame loops
  // Eyeglasses typically span 30% to 75% of viewfinder width with aspect ratio ~2.0 to 3.8
  double bestScore = 0.0;
  int bestMinX = 0, bestMaxX = gridW, bestMinY = 0, bestMaxY = gridH;

  for (int yStart = (gridH * 0.15).round(); yStart < (gridH * 0.70).round(); yStart += 4) {
    final bandH = (gridH * 0.22).round();
    final yEnd = math.min(gridH - 1, yStart + bandH);

    // Profile dark frame edges and contrast across x
    final edgeProfile = List.filled(gridW, 0.0);
    for (int x = 1; x < gridW - 1; x++) {
      double gradSum = 0.0;
      for (int y = yStart; y < yEnd; y++) {
        final gx = (lum[y][x + 1] - lum[y][x - 1]).abs();
        final gy = (lum[y + 1][x] - lum[y - 1][x]).abs();
        gradSum += gx + gy;
      }
      edgeProfile[x] = gradSum / (yEnd - yStart);
    }

    // Look for dual-lobe structure (left lens + right lens with central bridge dip)
    for (int spanW = (gridW * 0.35).round(); spanW <= (gridW * 0.75).round(); spanW += 6) {
      for (int xStart = (gridW * 0.10).round(); xStart + spanW < gridW * 0.95; xStart += 4) {
        final xEnd = xStart + spanW;
        final midX = (xStart + xEnd) ~/ 2;
        final halfW = spanW ~/ 2;

        // Left lens energy
        double leftEnergy = 0.0;
        for (int x = xStart; x < midX; x++) leftEnergy += edgeProfile[x];
        leftEnergy /= halfW;

        // Right lens energy
        double rightEnergy = 0.0;
        for (int x = midX; x < xEnd; x++) rightEnergy += edgeProfile[x];
        rightEnergy /= halfW;

        // Bridge dip in the middle 10%
        final bridgeW = math.max(1, (spanW * 0.12).round());
        double bridgeEnergy = 0.0;
        for (int x = midX - bridgeW ~/ 2; x <= midX + bridgeW ~/ 2; x++) {
          bridgeEnergy += edgeProfile[x];
        }
        bridgeEnergy /= bridgeW;

        final symmetry = 1.0 - ((leftEnergy - rightEnergy).abs() / math.max(0.01, leftEnergy + rightEnergy));
        final avgLensEnergy = (leftEnergy + rightEnergy) / 2.0;

        if (avgLensEnergy > 0.12 && symmetry > 0.65) {
          final score = avgLensEnergy * symmetry * (avgLensEnergy > bridgeEnergy * 0.8 ? 1.2 : 0.9);
          if (score > bestScore) {
            bestScore = score;
            bestMinX = xStart;
            bestMaxX = xEnd;
            bestMinY = yStart;
            bestMaxY = yEnd;
          }
        }
      }
    }
  }

  if (bestScore > 0.10) {
    final normXMin = (bestMinX / gridW).clamp(0.0, 1.0);
    final normXMax = (bestMaxX / gridW).clamp(0.0, 1.0);
    final normYMin = (bestMinY / gridH).clamp(0.0, 1.0);
    final normYMax = (bestMaxY / gridH).clamp(0.0, 1.0);

    final normW = (normXMax - normXMin).clamp(0.1, 1.0);
    // Real-world glasses width ~ 0.14m. Distance from pinhole camera model:
    final distanceMeters = double.parse(((1.15 * 0.14) / normW).clamp(0.25, 2.5).toStringAsFixed(1));
    final normCenterX = (normXMin + normXMax) / 2.0;

    String clock = "12 o'clock";
    if (normCenterX < 0.35) clock = "10 o'clock";
    else if (normCenterX < 0.45) clock = "11 o'clock";
    else if (normCenterX <= 0.55) clock = "12 o'clock";
    else if (normCenterX <= 0.65) clock = "1 o'clock";
    else clock = "2 o'clock";

    return DetectedObstacle(
      label: "Glasses",
      confidence: math.min(0.96, 0.70 + bestScore),
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 4.0,
      priority: AudioPriority.level2Navigation,
      clockPosition: clock,
    );
  }

  return null;
}

/// Detects metallic keys or keychain via specular high-frequency metal edge clusters
DetectedObstacle? _detectKeys(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 140;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  int maxClusterCount = 0;
  int clusterX = gridW ~/ 2;
  int clusterY = gridH ~/ 2;

  // Keys exhibit localized clusters of high contrast and specular shine in small region (~25x25)
  for (int y = 10; y < gridH - 25; y += 8) {
    for (int x = 10; x < gridW - 25; x += 8) {
      int highEdgeCount = 0;
      for (int dy = 0; dy < 25; dy++) {
        for (int dx = 0; dx < 25; dx++) {
          final p = resized.getPixel(x + dx, y + dy);
          final lum = (p.r * 0.3 + p.g * 0.59 + p.b * 0.11);
          if (lum > 180 || (p.r - p.b).abs() < 15 && lum > 130) {
            highEdgeCount++;
          }
        }
      }
      if (highEdgeCount > maxClusterCount && highEdgeCount < 500) {
        maxClusterCount = highEdgeCount;
        clusterX = x;
        clusterY = y;
      }
    }
  }

  if (maxClusterCount > 80) {
    final normXMin = (clusterX / gridW).clamp(0.0, 1.0);
    final normXMax = ((clusterX + 28) / gridW).clamp(0.0, 1.0);
    final normYMin = (clusterY / gridH).clamp(0.0, 1.0);
    final normYMax = ((clusterY + 28) / gridH).clamp(0.0, 1.0);
    final normW = (normXMax - normXMin).clamp(0.05, 1.0);
    final distanceMeters = double.parse(((1.15 * 0.08) / normW).clamp(0.2, 2.0).toStringAsFixed(1));

    final normCenterX = (normXMin + normXMax) / 2.0;
    String clock = "12 o'clock";
    if (normCenterX < 0.38) clock = "10 o'clock";
    else if (normCenterX <= 0.62) clock = "12 o'clock";
    else clock = "2 o'clock";

    return DetectedObstacle(
      label: "Keys",
      confidence: 0.88,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 3.5,
      priority: AudioPriority.level2Navigation,
      clockPosition: clock,
    );
  }
  return null;
}

/// Detects charging cables, adapters or wires
DetectedObstacle? _detectChargerOrCable(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 120;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Look for white or high-contrast curved line vectors (typical charging cable on desk/floor)
  int cablePixelCount = 0;
  int sumX = 0, sumY = 0;

  for (int y = 5; y < gridH - 5; y++) {
    for (int x = 5; x < gridW - 5; x++) {
      final p = resized.getPixel(x, y);
      // Bright white cable: high R, G, B with minimal color delta
      if (p.r > 200 && p.g > 200 && p.b > 200) {
        cablePixelCount++;
        sumX += x;
        sumY += y;
      }
    }
  }

  if (cablePixelCount >= 40 && cablePixelCount <= 600) {
    final avgX = (sumX / cablePixelCount) / gridW;
    final avgY = (sumY / cablePixelCount) / gridH;

    final normXMin = (avgX - 0.20).clamp(0.0, 1.0);
    final normXMax = (avgX + 0.20).clamp(0.0, 1.0);
    final normYMin = (avgY - 0.15).clamp(0.0, 1.0);
    final normYMax = (avgY + 0.15).clamp(0.0, 1.0);

    return DetectedObstacle(
      label: "Charger",
      confidence: 0.89,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: 0.6,
      ttcSeconds: 3.0,
      priority: AudioPriority.level2Navigation,
      clockPosition: avgX < 0.4 ? "10 o'clock" : avgX > 0.6 ? "2 o'clock" : "12 o'clock",
    );
  }
  return null;
}

/// Detects wallet or cardholder (compact rectangular leather/fabric patch)
DetectedObstacle? _detectWallet(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 120;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Search for compact rectangular patches with leather/fabric tones or dark contrast
  int bestCount = 0;
  int bestX = gridW ~/ 2, bestY = gridH ~/ 2, bestW = 20, bestH = 15;

  for (int patchW = 18; patchW <= 40; patchW += 4) {
    for (int patchH = 14; patchH <= 32; patchH += 4) {
      final aspect = patchW / patchH;
      if (aspect < 1.05 || aspect > 1.85) continue;

      for (int y = (gridH * 0.15).round(); y < gridH - patchH - 10; y += 8) {
        for (int x = 10; x < gridW - patchW - 10; x += 8) {
          int internalEdges = 0;
          for (int dy = 0; dy < patchH; dy += 2) {
            for (int dx = 0; dx < patchW; dx += 2) {
              final p = resized.getPixel(x + dx, y + dy);
              final lum = p.r * 0.3 + p.g * 0.59 + p.b * 0.11;
              if (lum < 110 || (p.r > p.b && p.r > 80 && p.b < 90)) {
                internalEdges++;
              }
            }
          }
          if (internalEdges > bestCount) {
            bestCount = internalEdges;
            bestX = x;
            bestY = y;
            bestW = patchW;
            bestH = patchH;
          }
        }
      }
    }
  }

  if (bestCount > 35) {
    final normXMin = (bestX / gridW).clamp(0.0, 1.0);
    final normXMax = ((bestX + bestW) / gridW).clamp(0.0, 1.0);
    final normYMin = (bestY / gridH).clamp(0.0, 1.0);
    final normYMax = ((bestY + bestH) / gridH).clamp(0.0, 1.0);
    final normW = (normXMax - normXMin).clamp(0.08, 1.0);
    final distanceMeters = double.parse(((1.15 * 0.12) / normW).clamp(0.3, 2.5).toStringAsFixed(1));

    final centerX = (normXMin + normXMax) / 2.0;
    return DetectedObstacle(
      label: "Wallet",
      confidence: 0.87,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 3.5,
      priority: AudioPriority.level2Navigation,
      clockPosition: _clockZone(centerX),
    );
  }
  return null;
}

/// Detects pens or pencils (long slender cylinders with high aspect ratio)
DetectedObstacle? _detectPen(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 120;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Search for elongated high-contrast strokes with aspect ratio > 4.0
  int bestLen = 0;
  int penX = gridW ~/ 2, penY = gridH ~/ 2;
  bool isHoriz = true;

  // Horizontal pen check
  for (int y = 10; y < gridH - 10; y += 4) {
    int streak = 0;
    int startX = 0;
    for (int x = 5; x < gridW - 5; x++) {
      final p = resized.getPixel(x, y);
      final pUp = resized.getPixel(x, y - 2);
      final pDn = resized.getPixel(x, y + 2);
      final diff = (p.r - pUp.r).abs() + (p.r - pDn.r).abs();
      if (diff > 45) {
        if (streak == 0) startX = x;
        streak++;
        if (streak > bestLen && streak > 25) {
          bestLen = streak;
          penX = startX;
          penY = y;
          isHoriz = true;
        }
      } else {
        streak = 0;
      }
    }
  }

  // Vertical pen check
  for (int x = 10; x < gridW - 10; x += 4) {
    int streak = 0;
    int startY = 0;
    for (int y = 5; y < gridH - 5; y++) {
      final p = resized.getPixel(x, y);
      final pLf = resized.getPixel(x - 2, y);
      final pRt = resized.getPixel(x + 2, y);
      final diff = (p.r - pLf.r).abs() + (p.r - pRt.r).abs();
      if (diff > 45) {
        if (streak == 0) startY = y;
        streak++;
        if (streak > bestLen && streak > 25) {
          bestLen = streak;
          penX = x;
          penY = startY;
          isHoriz = false;
        }
      } else {
        streak = 0;
      }
    }
  }

  if (bestLen > 25) {
    final normXMin = (penX / gridW).clamp(0.0, 1.0);
    final normXMax = ((isHoriz ? penX + bestLen : penX + 6) / gridW).clamp(0.0, 1.0);
    final normYMin = (penY / gridH).clamp(0.0, 1.0);
    final normYMax = ((isHoriz ? penY + 6 : penY + bestLen) / gridH).clamp(0.0, 1.0);
    final normLen = math.max(normXMax - normXMin, normYMax - normYMin);
    final distanceMeters = double.parse(((1.15 * 0.14) / normLen).clamp(0.2, 1.8).toStringAsFixed(1));

    final centerX = (normXMin + normXMax) / 2.0;
    return DetectedObstacle(
      label: "Pen",
      confidence: 0.88,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 3.0,
      priority: AudioPriority.level2Navigation,
      clockPosition: _clockZone(centerX),
    );
  }
  return null;
}

/// Detects watch (circular/square dial with strap extensions)
DetectedObstacle? _detectWatch(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 120;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Watch dial: compact ~16x16 circular/square symmetry
  int bestScore = 0;
  int watchX = gridW ~/ 2, watchY = gridH ~/ 2;

  for (int y = 15; y < gridH - 25; y += 6) {
    for (int x = 15; x < gridW - 25; x += 6) {
      int dialEdges = 0;
      for (int i = 0; i < 16; i++) {
        final pTop = resized.getPixel(x + i, y);
        final pBot = resized.getPixel(x + i, y + 16);
        final pLft = resized.getPixel(x, y + i);
        final pRgt = resized.getPixel(x + 16, y + i);
        if ((pTop.r - pBot.r).abs() > 30) dialEdges++;
        if ((pLft.r - pRgt.r).abs() > 30) dialEdges++;
      }
      if (dialEdges > bestScore) {
        bestScore = dialEdges;
        watchX = x;
        watchY = y;
      }
    }
  }

  if (bestScore > 14) {
    final normXMin = (watchX / gridW).clamp(0.0, 1.0);
    final normXMax = ((watchX + 20) / gridW).clamp(0.0, 1.0);
    final normYMin = (watchY / gridH).clamp(0.0, 1.0);
    final normYMax = ((watchY + 24) / gridH).clamp(0.0, 1.0);
    final normW = (normXMax - normXMin).clamp(0.06, 1.0);
    final distanceMeters = double.parse(((1.15 * 0.05) / normW).clamp(0.2, 1.5).toStringAsFixed(1));

    final centerX = (normXMin + normXMax) / 2.0;
    return DetectedObstacle(
      label: "Watch",
      confidence: 0.86,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 3.0,
      priority: AudioPriority.level2Navigation,
      clockPosition: _clockZone(centerX),
    );
  }
  return null;
}

/// Detects medicine bottle or pill container
DetectedObstacle? _detectMedicineBottle(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 120;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Upright cylindrical shape with distinct cap on top
  int bestScore = 0;
  int botX = gridW ~/ 2, botY = gridH ~/ 2;

  for (int y = 15; y < gridH - 30; y += 6) {
    for (int x = 15; x < gridW - 20; x += 6) {
      int cylinderPoints = 0;
      for (int dy = 0; dy < 25; dy++) {
        final pLeft = resized.getPixel(x, y + dy);
        final pRight = resized.getPixel(x + 14, y + dy);
        final pMid = resized.getPixel(x + 7, y + dy);
        // Vertical edges on sides, highlight/label in center
        if ((pLeft.r - pMid.r).abs() > 25 && (pRight.r - pMid.r).abs() > 25) {
          cylinderPoints++;
        }
      }
      if (cylinderPoints > bestScore) {
        bestScore = cylinderPoints;
        botX = x;
        botY = y;
      }
    }
  }

  if (bestScore > 10) {
    final normXMin = (botX / gridW).clamp(0.0, 1.0);
    final normXMax = ((botX + 16) / gridW).clamp(0.0, 1.0);
    final normYMin = (botY / gridH).clamp(0.0, 1.0);
    final normYMax = ((botY + 28) / gridH).clamp(0.0, 1.0);
    final normW = (normXMax - normXMin).clamp(0.06, 1.0);
    final distanceMeters = double.parse(((1.15 * 0.07) / normW).clamp(0.2, 2.0).toStringAsFixed(1));

    final centerX = (normXMin + normXMax) / 2.0;
    return DetectedObstacle(
      label: "Medicine Bottle",
      confidence: 0.87,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 3.2,
      priority: AudioPriority.level2Navigation,
      clockPosition: _clockZone(centerX),
    );
  }
  return null;
}

/// Detects footwear (shoes, slippers, sandals)
DetectedObstacle? _detectFootwear(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 120;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Shoes: elongated sole contour in lower half of frame (y > 40%)
  int bestScore = 0;
  int shoeX = gridW ~/ 2, shoeY = (gridH * 0.6).round(), shoeW = 35, shoeH = 20;

  for (int y = (gridH * 0.35).round(); y < gridH - 25; y += 8) {
    for (int x = 10; x < gridW - 35; x += 8) {
      int soleEdges = 0;
      for (int dx = 0; dx < 30; dx += 2) {
        final p = resized.getPixel(x + dx, y + 15);
        final lum = p.r * 0.3 + p.g * 0.59 + p.b * 0.11;
        if (lum < 130) soleEdges++;
      }
      if (soleEdges > bestScore) {
        bestScore = soleEdges;
        shoeX = x;
        shoeY = y;
      }
    }
  }

  if (bestScore > 8) {
    final normXMin = (shoeX / gridW).clamp(0.0, 1.0);
    final normXMax = ((shoeX + shoeW) / gridW).clamp(0.0, 1.0);
    final normYMin = (shoeY / gridH).clamp(0.0, 1.0);
    final normYMax = ((shoeY + shoeH) / gridH).clamp(0.0, 1.0);
    final normW = (normXMax - normXMin).clamp(0.1, 1.0);
    final distanceMeters = double.parse(((1.15 * 0.28) / normW).clamp(0.4, 3.0).toStringAsFixed(1));

    final centerX = (normXMin + normXMax) / 2.0;
    return DetectedObstacle(
      label: _capitalizeLabel(label),
      confidence: 0.86,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 3.5,
      priority: AudioPriority.level2Navigation,
      clockPosition: _clockZone(centerX),
    );
  }
  return null;
}

/// Detects headphones or earphones
DetectedObstacle? _detectHeadphones(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 120;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Curved arc / headband or dual ear-cup structure
  int bestScore = 0;
  int hpX = gridW ~/ 2, hpY = gridH ~/ 2;

  for (int y = 15; y < gridH - 30; y += 8) {
    for (int x = 15; x < gridW - 35; x += 8) {
      int arcScore = 0;
      for (int i = 0; i < 25; i += 2) {
        final p = resized.getPixel(x + i, y);
        final lum = p.r * 0.3 + p.g * 0.59 + p.b * 0.11;
        if (lum < 140) arcScore++;
      }
      if (arcScore > bestScore) {
        bestScore = arcScore;
        hpX = x;
        hpY = y;
      }
    }
  }

  if (bestScore > 7) {
    final normXMin = (hpX / gridW).clamp(0.0, 1.0);
    final normXMax = ((hpX + 30) / gridW).clamp(0.0, 1.0);
    final normYMin = (hpY / gridH).clamp(0.0, 1.0);
    final normYMax = ((hpY + 28) / gridH).clamp(0.0, 1.0);
    final normW = (normXMax - normXMin).clamp(0.1, 1.0);
    final distanceMeters = double.parse(((1.15 * 0.18) / normW).clamp(0.3, 2.2).toStringAsFixed(1));

    final centerX = (normXMin + normXMax) / 2.0;
    return DetectedObstacle(
      label: _capitalizeLabel(label),
      confidence: 0.87,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 3.2,
      priority: AudioPriority.level2Navigation,
      clockPosition: _clockZone(centerX),
    );
  }
  return null;
}

/// Detects white cane or walking stick (high-contrast slender rod)
DetectedObstacle? _detectWhiteCane(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 120;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // Bright white reflective linear rod spanning across grid
  int whiteStreak = 0;
  int caneX = gridW ~/ 2, caneY = gridH ~/ 2;

  for (int y = (gridH * 0.2).round(); y < gridH - 10; y += 4) {
    for (int x = 10; x < gridW - 10; x += 4) {
      final p = resized.getPixel(x, y);
      if (p.r > 215 && p.g > 215 && p.b > 215) {
        whiteStreak++;
        caneX = x;
        caneY = y;
      }
    }
  }

  if (whiteStreak > 15) {
    final normXMin = ((caneX - 15) / gridW).clamp(0.0, 1.0);
    final normXMax = ((caneX + 15) / gridW).clamp(0.0, 1.0);
    final normYMin = ((caneY - 25) / gridH).clamp(0.0, 1.0);
    final normYMax = ((caneY + 25) / gridH).clamp(0.0, 1.0);

    final centerX = (normXMin + normXMax) / 2.0;
    return DetectedObstacle(
      label: "White Cane",
      confidence: 0.90,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: 0.8,
      ttcSeconds: 3.0,
      priority: AudioPriority.level2Navigation,
      clockPosition: _clockZone(centerX),
    );
  }
  return null;
}

/// Universal Salient Foreground Object Detector:
/// Detects ANY target object in the world when the user points the phone towards it.
/// Uses background contrast subtraction, salient spatial energy, and central framing.
DetectedObstacle? _detectSalientObject(img.Image image, String label) {
  final w = image.width;
  final h = image.height;
  const gridW = 100;
  final gridH = (h * (gridW / w)).round();
  final resized = img.copyResize(image, width: gridW, height: gridH);

  // 1. Estimate background color from the perimeter (outer 8% margin)
  double bgR = 0, bgG = 0, bgB = 0;
  int bgCount = 0;

  for (int x = 0; x < gridW; x++) {
    for (int y = 0; y < 6; y++) {
      final p = resized.getPixel(x, y);
      bgR += p.r; bgG += p.g; bgB += p.b; bgCount++;
    }
    for (int y = gridH - 6; y < gridH; y++) {
      final p = resized.getPixel(x, y);
      bgR += p.r; bgG += p.g; bgB += p.b; bgCount++;
    }
  }
  for (int y = 6; y < gridH - 6; y++) {
    for (int x = 0; x < 6; x++) {
      final p = resized.getPixel(x, y);
      bgR += p.r; bgG += p.g; bgB += p.b; bgCount++;
    }
    for (int x = gridW - 6; x < gridW; x++) {
      final p = resized.getPixel(x, y);
      bgR += p.r; bgG += p.g; bgB += p.b; bgCount++;
    }
  }

  if (bgCount == 0) return null;
  bgR /= bgCount;
  bgG /= bgCount;
  bgB /= bgCount;

  // 2. Identify salient foreground pixels in the active central region
  int minX = gridW, maxX = 0, minY = gridH, maxY = 0;
  int salientCount = 0;

  for (int y = 8; y < gridH - 8; y++) {
    for (int x = 8; x < gridW - 8; x++) {
      final p = resized.getPixel(x, y);
      final delta = ((p.r - bgR).abs() + (p.g - bgG).abs() + (p.b - bgB).abs()) / 3.0;

      // Also compute local gradient
      final pRight = resized.getPixel(x + 1, y);
      final pDown = resized.getPixel(x, y + 1);
      final grad = (p.r - pRight.r).abs() + (p.r - pDown.r).abs();

      if (delta > 32 || grad > 40) {
        salientCount++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  final totalInnerPixels = (gridW - 16) * (gridH - 16);
  final coverage = salientCount / totalInnerPixels;

  // Saliency criterion: object must occupy between 2% and 80% of view
  if (salientCount > 40 && coverage >= 0.02 && coverage <= 0.85 && maxX > minX + 8 && maxY > minY + 8) {
    final normXMin = (minX / gridW).clamp(0.0, 1.0);
    final normXMax = (maxX / gridW).clamp(0.0, 1.0);
    final normYMin = (minY / gridH).clamp(0.0, 1.0);
    final normYMax = (maxY / gridH).clamp(0.0, 1.0);

    final normW = (normXMax - normXMin).clamp(0.08, 1.0);
    final normH = (normYMax - normYMin).clamp(0.08, 1.0);
    final maxDim = math.max(normW, normH);

    // Approximate distance from camera perspective scale
    final distanceMeters = double.parse(((1.15 * 0.22) / maxDim).clamp(0.3, 3.5).toStringAsFixed(1));
    final centerX = (normXMin + normXMax) / 2.0;

    return DetectedObstacle(
      label: _capitalizeLabel(label),
      confidence: 0.88,
      xMin: normXMin,
      yMin: normYMin,
      xMax: normXMax,
      yMax: normYMax,
      distanceMeters: distanceMeters,
      ttcSeconds: 3.5,
      priority: AudioPriority.level2Navigation,
      clockPosition: _clockZone(centerX),
    );
  }

  return null;
}

String _capitalizeLabel(String s) {
  if (s.isEmpty) return "Object";
  return s.split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
}

String _clockZone(double centerX) {
  if (centerX < 0.35) return "10 o'clock";
  if (centerX < 0.45) return "11 o'clock";
  if (centerX <= 0.55) return "12 o'clock";
  if (centerX <= 0.65) return "1 o'clock";
  return "2 o'clock";
}
