//
//  FlutterAudioVisualizerPlugin.swift
//  flutter_audio_visualizer
//
//  Created by Flutter Audio Visualizer
//

import Flutter
import UIKit
import AVFoundation
import Accelerate

public class FlutterAudioVisualizerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    private var fftSetup: FFTSetup?
    private var isPlaying = false
    
    private let fftSize = 1024
    private var audioFormat: AVAudioFormat?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "flutter_audio_visualizer", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "flutter_audio_visualizer/events", binaryMessenger: registrar.messenger())
        
        let instance = FlutterAudioVisualizerPlugin()
        instance.methodChannel = methodChannel
        instance.eventChannel = eventChannel
        
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            if let args = call.arguments as? [String: Any],
               let audioSessionId = args["audioSessionId"] as? Int {
                initialize(audioSessionId: audioSessionId, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "audioSessionId is required", details: nil))
            }
        case "start":
            start(result: result)
        case "stop":
            stop(result: result)
        case "setCaptureSize":
            if let args = call.arguments as? [String: Any],
               let size = args["size"] as? Int {
                setCaptureSize(size: size, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "size is required", details: nil))
            }
        case "initializeWithFile":
            if let args = call.arguments as? [String: Any],
               let filePath = args["filePath"] as? String {
                initializeWithFile(filePath: filePath, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "filePath is required", details: nil))
            }
        case "requestPermission":
            requestPermission(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func initialize(audioSessionId: Int, result: @escaping FlutterResult) {
        // iOS doesn't support audioSessionId like Android
        // We'll use a different approach for iOS
        result(true)
    }
    
    private func initializeWithFile(filePath: String, result: @escaping FlutterResult) {
        do {
            let url = URL(fileURLWithPath: filePath)
            audioFile = try AVAudioFile(forReading: url)
            audioFormat = audioFile?.processingFormat
            
            // Setup FFT
            setupFFT()
            
            result(true)
        } catch {
            result(FlutterError(code: "FILE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func start(result: @escaping FlutterResult) {
        guard let audioFile = audioFile, let audioFormat = audioFormat else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Audio file not initialized", details: nil))
            return
        }
        
        stop(result: { _ in })
        
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        
        guard let audioEngine = audioEngine, let audioPlayerNode = audioPlayerNode else {
            result(FlutterError(code: "ENGINE_ERROR", message: "Failed to create audio engine", details: nil))
            return
        }
        
        audioEngine.attach(audioPlayerNode)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        
        // Install tap to get audio data
        let bufferSize = AVAudioFrameCount(fftSize)
        audioPlayerNode.installTap(onBus: 0, bufferSize: bufferSize, format: audioFormat) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer: buffer)
        }
        
        do {
            try audioEngine.start()
            audioPlayerNode.scheduleFile(audioFile, at: nil)
            audioPlayerNode.play()
            isPlaying = true
            result(true)
        } catch {
            result(FlutterError(code: "ENGINE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func stop(result: @escaping FlutterResult) {
        audioPlayerNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioPlayerNode?.stop()
        isPlaying = false
        result(true)
    }
    
    private func setCaptureSize(size: Int, result: @escaping FlutterResult) {
        result(true)
    }
    
    private func requestPermission(result: @escaping FlutterResult) {
        // iOS doesn't require RECORD_AUDIO permission for playing local audio files
        // Just return true
        result(true)
    }
    
    private func setupFFT() {
        let log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData,
              let fftSetup = fftSetup else {
            return
        }
        
        let frameCount = Int(buffer.frameLength)
        let log2n = vDSP_Length(log2(Double(fftSize)))
        
        // Prepare input for FFT - use fftSize instead of fftSize / 2
        var realIn = [Float](repeating: 0, count: fftSize)
        var imagIn = [Float](repeating: 0, count: fftSize)
        
        // Copy audio data
        let copyCount = min(frameCount, fftSize)
        for i in 0..<copyCount {
            realIn[i] = channelData[0][i]
        }
        
        // Print PCM data (first 10 samples)
        print("PCM data (first 10): \(realIn.prefix(10).map { String(format: "%.3f", $0) }.joined(separator: ", "))")
        
        // Perform FFT
        var complexSplit = DSPSplitComplex(realp: &realIn, imagp: &imagIn)
        vDSP_fft_zrip(fftSetup, &complexSplit, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // Calculate magnitudes - vDSP_fft_zrip produces symmetric output, we only need first half
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvmags(&complexSplit, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
        
        // Print FFT data (first 20 values)
        print("FFT magnitudes (first 20): \(magnitudes.prefix(20).map { String(format: "%.3f", $0) }.joined(separator: ", "))")
        
        // vDSP_fft_zrip output is symmetric, take first half (low to high frequency)
        // Match Android: low to high frequency (left to right)
        let halfSize = fftSize / 4  // Take only first quarter to avoid symmetry
        var halfMagnitudes = [Float](repeating: 0, count: halfSize)
        for i in 0..<halfSize {
            halfMagnitudes[i] = magnitudes[i]
        }
        
        // Convert to Double array (no reversal needed)
        let fftData = halfMagnitudes.map { Double($0) }
        
        // Send to Flutter
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(fftData)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
