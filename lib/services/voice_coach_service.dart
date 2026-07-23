import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';

class VoiceCoachService {
  late FlutterTts _flutterTts;
  bool _initialized = false;

  // 防抖动：记录每种消息的最后播报时间
  final Map<String, DateTime> _lastSpeakMap = {};

  // 每分钟最多 8 条
  final List<DateTime> _speakTimestamps = [];
  static const int _maxPerMinute = 8;
  static const Duration _debounceSameMessage = Duration(seconds: 5);

  Future<void> initialize() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("zh-CN");
    await _flutterTts.setSpeechRate(0.55);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(0.9);
    _initialized = true;
  }

  /// 播报反馈消息，带防抖动和频率限制
  Future<void> speakFeedback(String message) async {
    if (!_initialized) return;

    final now = DateTime.now();

    // 防抖动：同一种消息至少间隔 5 秒
    if (_lastSpeakMap.containsKey(message)) {
      if (now.difference(_lastSpeakMap[message]!) < _debounceSameMessage) {
        return;
      }
    }

    // 每分钟上限检查
    _speakTimestamps.removeWhere(
      (t) => now.difference(t) > const Duration(minutes: 1),
    );
    if (_speakTimestamps.length >= _maxPerMinute) return;

    _lastSpeakMap[message] = now;
    _speakTimestamps.add(now);

    await _flutterTts.speak(message);
  }

  Future<void> stop() async {
    if (_initialized) {
      await _flutterTts.stop();
    }
  }

  void dispose() {
    _flutterTts.stop();
  }
}
