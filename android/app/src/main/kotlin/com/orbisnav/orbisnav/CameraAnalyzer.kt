package com.orbisnav.orbisnav

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import java.nio.ByteBuffer

/**
 * CameraAnalyzer: Real-time CameraX ImageAnalysis analyzer.
 * 
 * Enforces:
 * 1. Zero-heap JNI buffer passing (extracts direct ByteBuffer addresses without array copies).
 * 2. Thermal Governor frame decimation (steps down 30 -> 20 -> 15 -> 10 FPS based on thermal status).
 * 3. Immediate listener dispatch on Level 0/1 Hazard detection for zero-overlap audio preemption.
 */
class CameraAnalyzer(
    private val context: Context,
    private val onHazardDetected: (priorityLevel: Int, distanceMm: Long, ttcMs: Long) -> Unit
) : ImageAnalysis.Analyzer {

    companion object {
        private const val TAG = "CameraAnalyzer"

        init {
            try {
                System.loadLibrary("vision_engine")
                Log.i(TAG, "Native vision_engine library loaded successfully.")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load native vision_engine library: ${e.message}")
            }
        }
    }

    // Native JNI Declarations
    private external fun initVisionEngine(): Boolean
    private external fun processYuvFrame(
        yBuffer: ByteBuffer,
        uBuffer: ByteBuffer,
        vBuffer: ByteBuffer,
        width: Int,
        height: Int,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        rotationDegrees: Int
    ): LongArray?
    private external fun releaseVisionEngine()

    private var isInitialized = false
    private var frameCounter: Long = 0
    private var targetFps = 30
    private var lastProcessedFrameTimestamp: Long = 0

    init {
        isInitialized = try {
            initVisionEngine()
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing native vision engine: ${e.message}")
            false
        }
        setupThermalGovernor()
    }

    private fun setupThermalGovernor() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            powerManager?.addThermalStatusListener { status ->
                targetFps = when (status) {
                    PowerManager.THERMAL_STATUS_NONE -> 30
                    PowerManager.THERMAL_STATUS_LIGHT -> 20
                    PowerManager.THERMAL_STATUS_MODERATE -> 20
                    PowerManager.THERMAL_STATUS_SEVERE -> 15
                    PowerManager.THERMAL_STATUS_CRITICAL -> 10
                    PowerManager.THERMAL_STATUS_EMERGENCY -> 10
                    PowerManager.THERMAL_STATUS_SHUTDOWN -> 5
                    else -> 30
                }
                Log.w(TAG, "Thermal Governor updated target FPS: $targetFps (Status: $status)")
            }
        }
    }

    override fun analyze(imageProxy: ImageProxy) {
        frameCounter++

        // Thermal Governor Frame Decimation: skip frames if above target FPS budget
        val minFrameIntervalMs = 1000L / targetFps
        val now = System.currentTimeMillis()
        if (now - lastProcessedFrameTimestamp < minFrameIntervalMs) {
            imageProxy.close()
            return
        }
        lastProcessedFrameTimestamp = now

        try {
            if (!isInitialized) {
                imageProxy.close()
                return
            }

            val planes = imageProxy.planes
            if (planes.size < 3) {
                imageProxy.close()
                return
            }

            val yPlane = planes[0]
            val uPlane = planes[1]
            val vPlane = planes[2]

            val yBuffer = yPlane.buffer
            val uBuffer = uPlane.buffer
            val vBuffer = vPlane.buffer

            val width = imageProxy.width
            val height = imageProxy.height
            val rotation = imageProxy.imageInfo.rotationDegrees

            // Direct pointer invocation into native C++ zero-heap engine
            val results = processYuvFrame(
                yBuffer,
                uBuffer,
                vBuffer,
                width,
                height,
                yPlane.rowStride,
                uPlane.rowStride,
                uPlane.pixelStride,
                rotation
            )

            if (results != null && results.size >= 5) {
                val executionTimeMs = results[0]
                val isHazard = results[1] == 1L
                val priorityLevel = results[2].toInt()
                val distanceMm = results[3]
                val ttcMs = results[4]

                if (executionTimeMs > 30) {
                    Log.w(TAG, "Frame processing exceeded 30ms latency constraint: ${executionTimeMs}ms")
                }

                // If Level 0 (Critical) or Level 1 (Immediate Safety) hazard, trigger hard audio preemption
                if (isHazard && priorityLevel <= 1) {
                    onHazardDetected(priorityLevel, distanceMm, ttcMs)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception inside CameraAnalyzer: ${e.message}", e)
        } finally {
            // Must always close imageProxy to allow CameraX to ingest next frame
            imageProxy.close()
        }
    }

    fun release() {
        try {
            releaseVisionEngine()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing vision engine: ${e.message}")
        }
        isInitialized = false
    }
}
