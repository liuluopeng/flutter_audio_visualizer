
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class FlutterAudioVisualizer {
  static const MethodChannel _methodChannel = MethodChannel('flutter_audio_visualizer');
  static const EventChannel _eventChannel = EventChannel('flutter_audio_visualizer/events');

  static Stream<List<double>>? _fftDataStream;

  /// 请求录音权限
  static Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 检查录音权限
  static Future<bool> checkPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// 初始化Visualizer，需要传入audioSessionId (Android)
  static Future<bool> initialize(int audioSessionId) async {
    final bool success = await _methodChannel.invokeMethod('initialize', {'audioSessionId': audioSessionId});
    return success;
  }

  /// 初始化Visualizer，需要传入音频文件路径 (iOS)
  static Future<bool> initializeWithFile(String filePath) async {
    final bool success = await _methodChannel.invokeMethod('initializeWithFile', {'filePath': filePath});
    return success;
  }

  /// 开始获取频谱数据
  static Future<bool> start() async {
    final bool success = await _methodChannel.invokeMethod('start');
    return success;
  }

  /// 停止获取频谱数据
  static Future<bool> stop() async {
    final bool success = await _methodChannel.invokeMethod('stop');
    return success;
  }

  /// 获取FFT频谱数据流
  static Stream<List<double>> get fftDataStream {
    _fftDataStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      final List<dynamic> list = event as List;
      return list.map((item) => item as double).toList();
    });
    return _fftDataStream!;
  }

  /// 设置频谱数据的长度
  static Future<bool> setCaptureSize(int size) async {
    final bool success = await _methodChannel.invokeMethod('setCaptureSize', {'size': size});
    return success;
  }
}
