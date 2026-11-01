package com.orbisnav.orbisnav

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.RecognizerIntent
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger

/**
 * MainActivity: Native Android Audio Mutex and Hardware Preemption Controller.
 * 
 * Enforces:
 * 1. Zero Audio Overlap via TextToSpeech.QUEUE_FLUSH and immediate tts.stop().
 * 2. Strict 4-Tier Audio Priority Matrix:
 *    - Level 0 (Critical Hazard): Hard flush, continuous heavy haptic, immediate priority speech.
 *    - Level 1 (Immediate Safety): Hard flush lower tiers, dual-tap haptic, safety warning.
 *    - Level 2 (Navigation): Turn cues, clock-face orientation, flush Level 3 context.
 *    - Level 3 (Context / AI): Scene descriptions, low priority, preempted by Levels 0-2.
 * 3. AudioManager Transient Focus Handling to duck/pause system media.
 * 4. Thermal Governor status telemetry.
 */
class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {

    companion object {
        private const val TAG = "MainActivityAudioMutex"
        private const val CHANNEL_NAME = "com.orbisnav.orbisnav/audio_mutex"
        private const val CHANNEL_NAME_ALT = "com.example.orbisnav/audio_mutex"

        const val PRIORITY_LEVEL_0_CRITICAL = 0
        const val PRIORITY_LEVEL_1_SAFETY = 1
        const val PRIORITY_LEVEL_2_NAVIGATION = 2
        const val PRIORITY_LEVEL_3_CONTEXT = 3
        private const val REQUEST_CODE_SPEECH = 2001
    }

    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private lateinit var audioManager: AudioManager
    private var vibrator: Vibrator? = null
    private var methodChannel: MethodChannel? = null
    private var methodChannelAlt: MethodChannel? = null

    // Track active utterance priority tier
    private val currentActivePriority = AtomicInteger(-1)
    private var audioFocusRequest: AudioFocusRequest? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var initialMapsUrl: String? = null

    private fun extractMapsUrl(intent: Intent?): String? {
        if (intent == null) return null
        if (Intent.ACTION_VIEW == intent.action) {
            val data = intent.data
            if (data != null) {
                return data.toString()
            }
        } else if (Intent.ACTION_SEND == intent.action) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrBlank()) {
                return text
            }
        }
        return null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = extractMapsUrl(intent)
        if (url != null) {
            methodChannel?.invokeMethod("onMapsUrlReceived", url)
            methodChannelAlt?.invokeMethod("onMapsUrlReceived", url)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialMapsUrl = extractMapsUrl(intent)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        initVibrator()
        initTts()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = MethodChannel.MethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel?.setMethodCallHandler(handler)

        methodChannelAlt = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME_ALT)
        methodChannelAlt?.setMethodCallHandler(handler)
    }

    private fun initVibrator() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibratorManager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun initTts() {
        tts = TextToSpeech(applicationContext, this)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts?.setLanguage(Locale.US)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.w(TAG, "TTS language not supported or missing data, falling back to default.")
                tts?.language = Locale.getDefault()
            }
            tts?.setSpeechRate(1.1f)
            tts?.setPitch(1.0f)

            // Setup UtteranceProgressListener to accurately reset active priority
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    Log.d(TAG, "TTS Utterance started: $utteranceId")
                }

                override fun onDone(utteranceId: String?) {
                    Log.d(TAG, "TTS Utterance completed: $utteranceId")
                    currentActivePriority.set(-1)
                    abandonAudioFocus()
                    runOnUiThread {
                        methodChannel?.invokeMethod("onSpeechCompleted", mapOf("utteranceId" to utteranceId))
                        methodChannelAlt?.invokeMethod("onSpeechCompleted", mapOf("utteranceId" to utteranceId))
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    Log.e(TAG, "TTS Utterance error on: $utteranceId")
                    currentActivePriority.set(-1)
                    abandonAudioFocus()
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    Log.e(TAG, "TTS Utterance error: $errorCode on $utteranceId")
                    currentActivePriority.set(-1)
                    abandonAudioFocus()
                }
            })

            isTtsReady = true
            Log.i(TAG, "Hardware TextToSpeech initialized successfully.")
        } else {
            Log.e(TAG, "Failed to initialize Hardware TextToSpeech engine. Status: $status")
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "speak" -> {
                val text = call.argument<String>("text") ?: ""
                val priority = call.argument<Int>("priority") ?: PRIORITY_LEVEL_3_CONTEXT
                val hapticCue = call.argument<Boolean>("haptic") ?: true
                val utteranceId = call.argument<String>("utteranceId") ?: "utt_${System.currentTimeMillis()}"

                speakWithPriority(text, priority, hapticCue, utteranceId, result)
            }
            "stop" -> {
                hardStopAllSpeech()
                result.success(true)
            }
            "flushQueue" -> {
                tts?.stop()
                currentActivePriority.set(-1)
                abandonAudioFocus()
                result.success(true)
            }
            "triggerHaptic" -> {
                val type = call.argument<String>("type") ?: "medium"
                executeHapticPattern(type)
                result.success(true)
            }
            "getThermalStatus" -> {
                val thermalStatus = getSystemThermalStatus()
                result.success(thermalStatus)
            }
            "isReady" -> {
                result.success(isTtsReady)
            }
            "startVoiceInput" -> {
                startSpeechRecognition(result)
            }
            "getInitialMapsUrl" -> {
                val url = initialMapsUrl
                initialMapsUrl = null
                result.success(url)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startSpeechRecognition(result: MethodChannel.Result) {
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak the item you are looking for...")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            }
            pendingSpeechResult = result
            startActivityForResult(intent, REQUEST_CODE_SPEECH)
        } catch (e: Exception) {
            Log.e(TAG, "Speech recognition intent failed: ${e.message}")
            result.success("")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SPEECH) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val recognized = matches?.firstOrNull()?.trim() ?: ""
                pendingSpeechResult?.success(recognized)
            } else {
                pendingSpeechResult?.success("")
            }
            pendingSpeechResult = null
        }
    }

    /**
     * Executes speech synthesis adhering strictly to the Audio Priority Matrix.
     */
    private fun speakWithPriority(
        text: String,
        priority: Int,
        triggerHaptic: Boolean,
        utteranceId: String,
        result: MethodChannel.Result
    ) {
        if (!isTtsReady || tts == null) {
            Log.w(TAG, "TTS not ready yet; queueing discarded.")
            result.success(false)
            return
        }

        val active = currentActivePriority.get()

        // Core System Law 2: Zero Audio Overlap
        // If an active speech is of STRICTLY HIGHER priority (lower numeric value),
        // lower priority speech is dropped or preempted.
        if (active != -1 && active < priority) {
            Log.w(TAG, "Rejected audio for priority $priority because higher priority $active is active.")
            result.success(false)
            return
        }

        // Request audio focus
        requestAudioFocus()

        when (priority) {
            PRIORITY_LEVEL_0_CRITICAL -> {
                // Hard flush active TTS immediately
                tts?.stop()
                currentActivePriority.set(PRIORITY_LEVEL_0_CRITICAL)
                if (triggerHaptic) {
                    executeHapticPattern("continuous_heavy")
                }
                val params = Bundle().apply {
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
                    putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                }
                val speakResult = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                result.success(speakResult == TextToSpeech.SUCCESS)
            }

            PRIORITY_LEVEL_1_SAFETY -> {
                // Hard flush active speech if active is Level 2 or 3
                if (active >= PRIORITY_LEVEL_1_SAFETY) {
                    tts?.stop()
                }
                currentActivePriority.set(PRIORITY_LEVEL_1_SAFETY)
                if (triggerHaptic) {
                    executeHapticPattern("dual_tap")
                }
                val params = Bundle().apply {
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
                    putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                }
                val speakResult = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                result.success(speakResult == TextToSpeech.SUCCESS)
            }

            PRIORITY_LEVEL_2_NAVIGATION -> {
                // Preempt Level 3 Context if active
                if (active == PRIORITY_LEVEL_3_CONTEXT) {
                    tts?.stop()
                }
                currentActivePriority.set(PRIORITY_LEVEL_2_NAVIGATION)
                if (triggerHaptic) {
                    executeHapticPattern("single_pulse")
                }
                val params = Bundle().apply {
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 0.9f)
                    putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                }
                val queueMode = if (active == PRIORITY_LEVEL_3_CONTEXT || active == -1) {
                    TextToSpeech.QUEUE_FLUSH
                } else {
                    TextToSpeech.QUEUE_ADD
                }
                val speakResult = tts?.speak(text, queueMode, params, utteranceId)
                result.success(speakResult == TextToSpeech.SUCCESS)
            }

            PRIORITY_LEVEL_3_CONTEXT -> {
                // Lowest priority: only execute if channel is completely clear
                if (active != -1) {
                    Log.d(TAG, "Level 3 speech dropped due to busy audio channel ($active)")
                    result.success(false)
                    return
                }
                currentActivePriority.set(PRIORITY_LEVEL_3_CONTEXT)
                val params = Bundle().apply {
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 0.8f)
                    putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                }
                val speakResult = tts?.speak(text, TextToSpeech.QUEUE_ADD, params, utteranceId)
                result.success(speakResult == TextToSpeech.SUCCESS)
            }

            else -> {
                tts?.speak(text, TextToSpeech.QUEUE_ADD, null, utteranceId)
                result.success(true)
            }
        }
    }

    private fun hardStopAllSpeech() {
        tts?.stop()
        currentActivePriority.set(-1)
        vibrator?.cancel()
        abandonAudioFocus()
    }

    private fun executeHapticPattern(patternType: String) {
        val vib = vibrator ?: return
        if (!vib.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            when (patternType) {
                "continuous_heavy" -> {
                    // Level 0: 3 rapid aggressive heavy pulses
                    val timings = longArrayOf(0, 150, 40, 150, 40, 200)
                    val amplitudes = intArrayOf(0, 255, 0, 255, 0, 255)
                    vib.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
                }
                "dual_tap" -> {
                    // Level 1: Dual crisp tap
                    val timings = longArrayOf(0, 70, 60, 70)
                    val amplitudes = intArrayOf(0, 220, 0, 220)
                    vib.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
                }
                "single_pulse" -> {
                    // Level 2: Discrete directional pulse
                    vib.vibrate(VibrationEffect.createOneShot(80, VibrationEffect.DEFAULT_AMPLITUDE))
                }
                else -> {
                    vib.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
                }
            }
        } else {
            @Suppress("DEPRECATION")
            when (patternType) {
                "continuous_heavy" -> vib.vibrate(longArrayOf(0, 150, 40, 150, 40, 200), -1)
                "dual_tap" -> vib.vibrate(longArrayOf(0, 70, 60, 70), -1)
                else -> vib.vibrate(80)
            }
        }
    }

    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(audioAttributes)
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener { /* Focus changes */ }
                .build()

            audioFocusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_ACCESSIBILITY,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }

    private fun getSystemThermalStatus(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            powerManager?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
        } else {
            0
        }
    }

    override fun onDestroy() {
        hardStopAllSpeech()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
