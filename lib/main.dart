// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:typed_data';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LivePhotoGuideApp());
}

class LivePhotoGuideApp extends StatelessWidget {
  const LivePhotoGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '摄影指导',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const GuideScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  FlutterTts _flutterTts = FlutterTts();
  PoseDetector? _poseDetector;
  bool _isInitialized = false;
  bool _isAnalyzing = false;
  String _guideText = '';
  Timer? _frameTimer;
  String? _lastCommand;
  DateTime _lastSpeakTime = DateTime(2000);
  int _speakCount = 0;
  Timer? _rateLimitReset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  Future<void> _initAll() async {
    await _flutterTts.setLanguage("zh-CN");
    await _flutterTts.setSpeechRate(0.48);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(0.85);
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
    await _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() => _guideText = '需要相机权限');
      }
      return;
    }
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() => _isInitialized = true);

    _frameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _captureAndAnalyze();
    });
  }

  Future<void> _captureAndAnalyze() async {
    if (_isAnalyzing || _controller == null || !_controller!.value.isInitialized)
      return;
    _isAnalyzing = true;
    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: _controller!.value.previewSize!,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.yuv420,
          bytesPerRow: 0,
        ),
      );
      final poses = await _poseDetector!.processImage(inputImage);
      String? rawGuide;
      if (poses.isNotEmpty) {
        final pose = poses.first;
        rawGuide = _evaluatePose(pose, _controller!.value.previewSize!.height);
      }
      final approved = _stateMachine(rawGuide);
      if (approved != null && mounted) {
        _flutterTts.speak(approved);
        setState(() => _guideText = approved);
      }
    } catch (_) {}
    _isAnalyzing = false;
  }

  String? _evaluatePose(Pose pose, double imageHeight) {
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (nose != null) {
      final ratio = nose.y / imageHeight;
      if (ratio < 0.22) return '手机稍微抬高一点';
      if (ratio > 0.62) return '手机稍微放低一点';
      final z = nose.z;
      if (z < -0.18) return '后退一步';
      if (z > -0.02) return '往前走一步';
    }

    if (leftShoulder != null && rightShoulder != null) {
      final dy = (rightShoulder.y - leftShoulder.y).abs();
      final dx = (rightShoulder.x - leftShoulder.x).abs();
      final angle = (dy / (dx + 0.001)) * 180 / 3.14159;
      if (angle > 12) return '肩膀放松';
    }

    return null;
  }

  String? _stateMachine(String? newCmd) {
    if (newCmd == null || newCmd.isEmpty) return null;
    final now = DateTime.now();
    if (now.difference(_lastSpeakTime) < const Duration(seconds: 3)) return null;
    if (newCmd == _lastCommand &&
        now.difference(_lastSpeakTime) < const Duration(seconds: 10)) return null;
    _rateLimitReset ??= Timer(const Duration(minutes: 1), () {
      _speakCount = 0;
      _rateLimitReset = null;
    });
    if (_speakCount >= 5) return null;
    _lastCommand = newCmd;
    _lastSpeakTime = now;
    _speakCount++;
    return newCmd;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _frameTimer?.cancel();
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('正在启动相机...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          Positioned(
            top: 0, left: 0, right: 0, height: 60,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black45, Colors.transparent],
                ),
              ),
            ),
          ),
          if (_guideText.isNotEmpty)
            Positioned(
              bottom: 140, left: 24, right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Text(
                  _guideText,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.w500, letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            bottom: 48, left: 0, right: 0,
            child: Center(
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _rateLimitReset?.cancel();
    _controller?.dispose();
    _poseDetector?.close();
    _flutterTts.stop();
    super.dispose();
  }
}
