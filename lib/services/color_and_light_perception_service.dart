import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Result of Color & Ambient Luminance perception.
class ColorAndLightResult {
  final String dominantColor;
  final int lightLevelPercent;
  final String lightDescription;

  const ColorAndLightResult({
    required this.dominantColor,
    required this.lightLevelPercent,
    required this.lightDescription,
  });
}

/// Service providing on-device color identification and luminance measurement
/// modeled after Microsoft Seeing AI Color and Light channels.
class ColorAndLightPerceptionService {
  /// Estimates dominant color at the center of the camera frame.
  String estimateDominantColor(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return "Neutral";
      final centerX = decoded.width ~/ 2;
      final centerY = decoded.height ~/ 2;
      int rSum = 0, gSum = 0, bSum = 0, count = 0;
      const sampleRadius = 15;
      for (int dy = -sampleRadius; dy <= sampleRadius; dy += 4) {
        for (int dx = -sampleRadius; dx <= sampleRadius; dx += 4) {
          final px = (centerX + dx).clamp(0, decoded.width - 1);
          final py = (centerY + dy).clamp(0, decoded.height - 1);
          final pixel = decoded.getPixel(px, py);
          rSum += pixel.r.toInt();
          gSum += pixel.g.toInt();
          bSum += pixel.b.toInt();
          count++;
        }
      }
      if (count == 0) return "Neutral";
      final r = rSum ~/ count;
      final g = gSum ~/ count;
      final b = bSum ~/ count;

      final brightness = (0.299 * r + 0.587 * g + 0.114 * b).toInt();
      final maxVal = [r, g, b].reduce((x, y) => x > y ? x : y);
      final minVal = [r, g, b].reduce((x, y) => x < y ? x : y);
      final delta = maxVal - minVal;

      if (brightness < 38) return "Black";
      if (brightness > 220 && delta < 25) return "White";
      if (delta < 22) return "Gray";

      double hue = 0;
      if (delta > 0) {
        if (maxVal == r) {
          hue = 60 * (((g - b) / delta) % 6);
        } else if (maxVal == g) {
          hue = 60 * (((b - r) / delta) + 2);
        } else {
          hue = 60 * (((r - g) / delta) + 4);
        }
        if (hue < 0) hue += 360;
      }

      if (hue >= 345 || hue < 15) return "Red";
      if (hue >= 15 && hue < 45) return "Orange";
      if (hue >= 45 && hue < 70) return "Yellow";
      if (hue >= 70 && hue < 165) return "Green";
      if (hue >= 165 && hue < 200) return "Cyan";
      if (hue >= 200 && hue < 260) return "Blue";
      if (hue >= 260 && hue < 290) return "Purple";
      if (hue >= 290 && hue < 345) return "Pink";
      return "Neutral";
    } catch (_) {
      return "Neutral";
    }
  }

  /// Estimates overall frame luminance percentage (0 to 100%).
  int estimateLightLevel(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return 50;
      const step = 10;
      int totalLuma = 0;
      int samples = 0;
      for (int y = 0; y < decoded.height; y += step) {
        for (int x = 0; x < decoded.width; x += step) {
          final pixel = decoded.getPixel(x, y);
          final luma = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).toInt();
          totalLuma += luma;
          samples++;
        }
      }
      if (samples == 0) return 50;
      final avg = totalLuma ~/ samples;
      return ((avg / 255.0) * 100).clamp(0, 100).toInt();
    } catch (_) {
      return 50;
    }
  }

  /// Generates descriptive natural speech for luminance percentage.
  String getLightDescription(int lumaPercent) {
    if (lumaPercent > 80) {
      return "Very bright direct light";
    } else if (lumaPercent < 25) {
      return "Dark or low light";
    } else {
      return "Good indoor illumination";
    }
  }

  /// Analyzes both color and light in a single pass.
  ColorAndLightResult analyzeColorAndLight(Uint8List bytes) {
    final color = estimateDominantColor(bytes);
    final light = estimateLightLevel(bytes);
    final desc = getLightDescription(light);
    return ColorAndLightResult(
      dominantColor: color,
      lightLevelPercent: light,
      lightDescription: desc,
    );
  }
}
