package com.example.flutter_audio_visualizer

import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.math.abs
import kotlin.math.hypot

/** FlutterAudioVisualizerPlugin */
class FlutterAudioVisualizerPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null
    private var visualizer: Visualizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var audioSessionId: Int = 0
    private var captureSize: Int = Visualizer.getCaptureSizeRange()[1]

    private val permissionsGranted: Boolean
        get() = context?.let {
            ContextCompat.checkSelfPermission(
                it,
                android.Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        } ?: false

    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "flutter_audio_visualizer")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "flutter_audio_visualizer/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                val audioSessionId = call.argument<Int>("audioSessionId") ?: 0
                this.audioSessionId = audioSessionId
                android.util.Log.d("FlutterAudioVisualizer", "initialize called with audioSessionId: $audioSessionId")
                result.success(true)
            }
            "start" -> {
                android.util.Log.d("FlutterAudioVisualizer", "start called, permissionsGranted: $permissionsGranted")
                if (!permissionsGranted) {
                    android.util.Log.e("FlutterAudioVisualizer", "Permissions not granted")
                    result.success(false)
                    return
                }
                startVisualizer()
                result.success(true)
            }
            "stop" -> {
                stopVisualizer()
                result.success(true)
            }
            "setCaptureSize" -> {
                val size = call.argument<Int>("size") ?: Visualizer.getCaptureSizeRange()[1]
                captureSize = size
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startVisualizer() {
        stopVisualizer()
        try {
            android.util.Log.d("FlutterAudioVisualizer", "Creating Visualizer with audioSessionId: $audioSessionId")
            visualizer = Visualizer(audioSessionId)
            visualizer?.apply {
                captureSize = this@FlutterAudioVisualizerPlugin.captureSize
                android.util.Log.d("FlutterAudioVisualizer", "Visualizer created, captureSize: $captureSize")
                setDataCaptureListener(
                    object : Visualizer.OnDataCaptureListener {
                        override fun onWaveFormDataCapture(
                            visualizer: Visualizer,
                            waveform: ByteArray,
                            samplingRate: Int
                        ) {
                            // 暂不处理波形数据
                        }

                        override fun onFftDataCapture(
                            visualizer: Visualizer,
                            fft: ByteArray,
                            samplingRate: Int
                        ) {
                            // 处理FFT数据
                            android.util.Log.d("FlutterAudioVisualizer", "onFftDataCapture called, fft size: ${fft.size}")
                            val fftData = processFftData(fft)
                            android.util.Log.d("FlutterAudioVisualizer", "Processed FFT data, sending ${fftData.size} values")
                            eventSink?.success(fftData)
                        }
                    },
                    Visualizer.getMaxCaptureRate(),
                    false,
                    true
                )
                enabled = true
                android.util.Log.d("FlutterAudioVisualizer", "Visualizer enabled")
            }
        } catch (e: Exception) {
            android.util.Log.e("FlutterAudioVisualizer", "Error starting visualizer", e)
            e.printStackTrace()
        }
    }

    private fun processFftData(fft: ByteArray): List<Double> {
        val f = fft.size / 2
        val floatArray = FloatArray(f + 1)
        floatArray[0] = abs(fft[1].toInt()).toFloat()
        var j = 1
        var i = 2
        while (i < f * 2) {
            floatArray[j] = hypot(fft[i].toDouble(), fft[i + 1].toDouble()).toFloat()
            i += 2
            j++
        }
        
        // Print FFT data (first 20 values)
        val first20 = floatArray.take(20).joinToString(", ") { "%.3f".format(it) }
        android.util.Log.d("FlutterAudioVisualizer", "FFT magnitudes (first 20): $first20")
        
        // 转换为List<Double>并返回
        return floatArray.map { it.toDouble() }
    }

    private fun stopVisualizer() {
        visualizer?.apply {
            enabled = false
            release()
        }
        visualizer = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        stopVisualizer()
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        context = null
    }
}
