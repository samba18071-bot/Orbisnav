# ProGuard / R8 Rules for OrbisNav / AI-Eyes Assistive Vision

# Preserve JNI export methods called from C++
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve CameraAnalyzer and JNI bindings
-keep class com.orbisnav.orbisnav.CameraAnalyzer { *; }
-keep class com.example.orbisnav.CameraAnalyzer { *; }
-keep class com.orbisnav.orbisnav.MainActivity { *; }
-keep class com.example.orbisnav.MainActivity { *; }

# Preserve CameraX classes and reflection calls
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.camera2.** { *; }
-keep class androidx.camera.lifecycle.** { *; }
-keep class androidx.camera.view.** { *; }
-dontwarn androidx.camera.**

# Preserve ONNX Runtime classes if present
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Flutter framework preservation
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preserve annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
