import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_audio_visualizer/flutter_audio_visualizer.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Visualizer Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AudioVisualizerScreen(),
    );
  }
}

class AudioVisualizerScreen extends StatefulWidget {
  const AudioVisualizerScreen({super.key});

  @override
  State<AudioVisualizerScreen> createState() => _AudioVisualizerScreenState();
}

class _AudioVisualizerScreenState extends State<AudioVisualizerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<double> _fftData = List.filled(64, 0.0);
  bool _isPlaying = false;
  int? _audioSessionId;

  // iOS specific
  String? _audioFilePath;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
    _setupVisualizer();
  }

  Future<void> _setupAudioPlayer() async {
    if (Platform.isAndroid) {
      // Android: 监听audioSessionId变化
      _audioPlayer.androidAudioSessionIdStream.listen((sessionId) {
        if (sessionId != null && sessionId != _audioSessionId) {
          _audioSessionId = sessionId;
          _initializeVisualizer();
        }
      });
    } else if (Platform.isIOS) {
      // iOS: 获取音频文件路径
      _audioFilePath = await _getAudioFilePath();
    }

    // 设置音频源
    await _audioPlayer.setAsset('assets/audio/sweep.mp3');
  }

  Future<String> _getAudioFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/sweep.mp3');

    if (!await file.exists()) {
      final byteData = await rootBundle.load('assets/audio/sweep.mp3');
      await file.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );
    }

    return file.path;
  }

  Future<void> _setupVisualizer() async {
    if (Platform.isAndroid) {
      // 请求权限
      final hasPermission = await FlutterAudioVisualizer.requestPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('需要录音权限来显示音频频谱')));
        }
        return;
      }
    }

    // 监听频谱数据
    FlutterAudioVisualizer.fftDataStream.listen((data) {
      print(
        'Flutter received FFT data (${Platform.operatingSystem}): ${data.take(20).map((e) => e.toStringAsFixed(3)).join(', ')}',
      );
      if (mounted) {
        setState(() {
          _fftData = data;
        });
      }
    });
  }

  Future<void> _initializeVisualizer() async {
    if (Platform.isAndroid) {
      // Android: 使用audioSessionId
      if (_audioSessionId != null) {
        await FlutterAudioVisualizer.initialize(_audioSessionId!);
        await FlutterAudioVisualizer.start();
      }
    } else if (Platform.isIOS) {
      // iOS: 使用音频文件路径
      if (_audioFilePath != null) {
        await FlutterAudioVisualizer.initializeWithFile(_audioFilePath!);
        await FlutterAudioVisualizer.start();
      }
    }
  }

  Future<void> _togglePlay() async {
    if (Platform.isIOS) {
      // iOS: 使用插件播放音频
      if (_isPlaying) {
        await FlutterAudioVisualizer.stop();
      } else {
        await _initializeVisualizer();
      }
    } else {
      // Android: 使用just_audio播放音频
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  @override
  void dispose() {
    FlutterAudioVisualizer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Audio Visualizer Demo (${Platform.operatingSystem})'),
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: _buildSpectrumVisualizer())),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FloatingActionButton(
              onPressed: _togglePlay,
              child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpectrumVisualizer() {
    return SizedBox(
      height: 300,
      width: double.infinity,
      child: CustomPaint(painter: SpectrumPainter(_fftData)),
    );
  }
}

class SpectrumPainter extends CustomPainter {
  final List<double> fftData;

  SpectrumPainter(this.fftData);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final barWidth = size.width / fftData.length;
    final maxHeight = size.height;

    for (int i = 0; i < fftData.length; i++) {
      // 归一化FFT数据到0-1范围
      final normalizedValue = fftData[i] / 100.0;
      final barHeight = normalizedValue * maxHeight;

      final rect = Rect.fromLTWH(
        i * barWidth,
        size.height - barHeight,
        barWidth - 2,
        barHeight,
      );

      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) {
    return oldDelegate.fftData != fftData;
  }
}
