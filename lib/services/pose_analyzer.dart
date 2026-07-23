import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class AnalysisResult {
  final bool isPerfect;
  final String? suggestion;
  final bool faceTooDark;
  final bool badAngle;
  final bool offGoldenPoint;

  AnalysisResult({
    required this.isPerfect,
    this.suggestion,
    this.faceTooDark = false,
    this.badAngle = false,
    this.offGoldenPoint = false,
  });

  static AnalysisResult perfect() {
    return AnalysisResult(isPerfect: true);
  }
}

class PoseAnalyzer {
  /// 分析姿态，返回 AnalysisResult
  AnalysisResult analyze(Pose pose, double imageWidth, double imageHeight) {
    final nose = pose.landmarks[PoseLandmarkType.nose];

    if (nose == null) {
      return AnalysisResult(isPerfect: false);
    }

    // 光线提醒（优先级最高）
    if (nose.z < -0.25) {
      return AnalysisResult(
        isPerfect: false,
        faceTooDark: true,
        suggestion: '光线有点暗，稍微迎着光一点，让脸部更通透。',
      );
    }

    // 角度建议
    final noseYRatio = nose.y / imageHeight;
    if (noseYRatio < 0.18) {
      return AnalysisResult(
        isPerfect: false,
        badAngle: true,
        suggestion: '稍微调整一下镜头角度，平视会让画面更有亲和力。',
      );
    }
    if (noseYRatio > 0.70) {
      return AnalysisResult(
        isPerfect: false,
        badAngle: true,
        suggestion: '稍微调整一下镜头角度，平视会让画面更有亲和力。',
      );
    }

    // 三分法构图
    final noseXRatio = nose.x / imageWidth;
    final inGoldenLeft = noseXRatio >= 0.28 && noseXRatio <= 0.38;
    final inGoldenRight = noseXRatio >= 0.62 && noseXRatio <= 0.72;
    if (!inGoldenLeft && !inGoldenRight) {
      return AnalysisResult(
        isPerfect: false,
        offGoldenPoint: true,
        suggestion: '尝试将主体放在画面的三分之一处，构图会更生动哦。',
      );
    }

    // 肩膀角度检测（原有逻辑保留）
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (leftShoulder != null && rightShoulder != null) {
      final dy = (rightShoulder.y - leftShoulder.y).abs();
      final dx = (rightShoulder.x - leftShoulder.x).abs();
      final angle = (dy / (dx + 0.001)) * 180 / 3.14159;
      if (angle > 12) {
        return AnalysisResult(
          isPerfect: false,
          suggestion: '肩膀放松一点，自然的状态最上镜。',
        );
      }
    }

    // 全部通过则为完美
    return AnalysisResult.perfect();
  }
}
