import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:live_photo_guide/services/voice_coach_service.dart';
import 'package:live_photo_guide/services/pose_analyzer.dart';
import 'dart:async';
import 'dart:typed_data';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  PoseDetector? _poseDetector;
  bool _isInitialized = false;
  bool _isAnalyzing = false;

  final VoiceCoachService _voiceCoach = VoiceCoachService();
  final PoseAnalyzer _poseAnalyzer = PoseAnalyzer();

  String _suggestion = '';
  bool _isPerfect = false;

  Timer? _frameTimer;

  // 完美帧计数器
  int _perfectFrameCount = 0;
  static const int _perfectFrameTrigger = 2; // 连续2帧（每帧约1秒）= 2秒
  bool _perfectSequenceTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  Future<void> _initAll() async {
    await _voiceCoach.initialize();
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
        setState(() => _suggestion = '需要相机权限');
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
    if (_isAnalyzing || _controller == null || !_controller!.value.isInitialized) {
      return;
    }
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
      if (poses.isNotEmpty) {
        final pose = poses.first;
        final result = _poseAnalyzer.analyze(
          pose,
          _controller!.value.previewSize!.width,
          _controller!.value.previewSize!.height,
        );

        if (result.isPerfect) {
          _perfectFrameCount++;
          if (_perfectFrameCount >= _perfectFrameTrigger &&
              !_perfectSequenceTriggered) {
            _perfectSequenceTriggered = true;
            _voiceCoach.speakFeedback(
              '状态非常好！保持这个眼神，准备抓拍……3、2、1！',
            );
          }
          if (mounted) {
            setState(() {
              _isPerfect = true;
              _suggestion = '完美';
            });
          }
        } else {
          _perfectFrameCount = 0;
          _perfectSequenceTriggered = false;
          if (result.suggestion != null) {
            _voiceCoach.speakFeedback(result.suggestion!);
            if (mounted) {
              setState(() {
                _isPerfect = false;
                _suggestion = result.suggestion!;
              });
            }
          }
        }
      }
    } catch (_) {}
    _isAnalyzing = false;
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
        backgroundColor: Colors.black,
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
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          // 顶部渐变遮罩
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 60,
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
          // 底部横幅提示
          if (_suggestion.isNotEmpty)
            Positioned(
              bottom: 140,
              left: 24,
              right: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Text(
                  _suggestion,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // 底部快门装饰
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 72,
                height: 72,
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
    _controller?.dispose();
    _poseDetector?.close();
    _voiceCoach.dispose();
    super.dispose();
  }
}
