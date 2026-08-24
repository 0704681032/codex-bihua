class StrokePlayerState {
  const StrokePlayerState({
    required this.currentStrokeIndex,
    required this.isPlaying,
    required this.speed,
    required this.progress,
    required this.totalStrokes,
    this.strokeWeights = const <double>[],
  });

  factory StrokePlayerState.initial({
    required int totalStrokes,
    List<double> strokeWeights = const <double>[],
  }) {
    return StrokePlayerState(
      currentStrokeIndex: totalStrokes,
      isPlaying: false,
      speed: 0.9,
      progress: totalStrokes > 0 ? 1 : 0,
      totalStrokes: totalStrokes,
      strokeWeights: strokeWeights,
    );
  }

  final int currentStrokeIndex;
  final bool isPlaying;
  final double speed;
  final double progress;
  final int totalStrokes;

  /// Per-stroke duration factors normalized to the longest stroke
  /// (longest = 1.0). A 点 with weight 0.3 therefore animates roughly
  /// three times faster than a full-length 横. An empty list means every
  /// stroke plays with the same duration.
  final List<double> strokeWeights;

  bool get completed => currentStrokeIndex >= totalStrokes;

  double weightAt(int index) {
    if (index < 0 || index >= strokeWeights.length) {
      return 1;
    }
    return strokeWeights[index];
  }

  StrokePlayerState copyWith({
    int? currentStrokeIndex,
    bool? isPlaying,
    double? speed,
    double? progress,
    int? totalStrokes,
    List<double>? strokeWeights,
  }) {
    return StrokePlayerState(
      currentStrokeIndex: currentStrokeIndex ?? this.currentStrokeIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      progress: progress ?? this.progress,
      totalStrokes: totalStrokes ?? this.totalStrokes,
      strokeWeights: strokeWeights ?? this.strokeWeights,
    );
  }
}
