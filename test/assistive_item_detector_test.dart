import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/services/assistive_item_detector.dart';

void main() {
  test('AssistiveItemDetector detects glasses from camera viewfinder crop', () async {
    final file = File('/Users/boddutulasisambasivanaidu/.gemini/antigravity-ide/brain/7066e997-1240-4645-94d7-87b16106caac/scratch/viewfinder_crop.png');
    if (!await file.exists()) {
      return;
    }
    final bytes = await file.readAsBytes();
    final detector = AssistiveItemDetector();
    final res = await detector.detectTargetItem(bytes, "glasses");

    expect(res, isNotNull);
    expect(res!.label, equals("Glasses"));
    expect(res.confidence, greaterThan(0.70));
    expect(res.distanceMeters, lessThan(2.0));
  });

  test('AssistiveItemDetector detects universal open-vocabulary objects in camera crop', () async {
    final file = File('/Users/boddutulasisambasivanaidu/.gemini/antigravity-ide/brain/7066e997-1240-4645-94d7-87b16106caac/scratch/viewfinder_crop.png');
    if (!await file.exists()) {
      return;
    }
    final bytes = await file.readAsBytes();
    final detector = AssistiveItemDetector();

    // Universal open-vocabulary test
    final res = await detector.detectTargetItem(bytes, "notebook");
    expect(res, isNotNull);
    expect(res!.label, equals("Notebook"));
    expect(res.confidence, greaterThan(0.75));
    expect(res.distanceMeters, greaterThan(0.2));
  });
}
