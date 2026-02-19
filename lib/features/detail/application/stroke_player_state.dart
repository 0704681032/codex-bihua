class StrokePlayerState {
  const StrokePlayerState({
    required this.currentStrokeIndex,
    required this.isPlaying,
    required this.speed,
    required this.progress,
    required this.totalStrokes,
  });

  factory StrokePlayerState.initial({required int totalStrokes}) {
    return StrokePlayerState(
      currentStrokeIndex: totalStrokes,
      isPlaying: false,
      speed: 0.9,
      progress: totalStrokes > 0 ? 1 : 0,
      totalStrokes: totalStrokes,
    );
  }

  final int currentStrokeIndex;
  final bool isPlaying;
  final double speed;
  final double progress;
  final int totalStrokes;

  bool get completed => currentStrokeIndex >= totalStrokes;

  StrokePlayerState copyWith({
    int? currentStrokeIndex,
    bool? isPlaying,
    double? speed,
    double? progress,
    int? totalStrokes,
  }) {
    return StrokePlayerState(
      currentStrokeIndex: currentStrokeIndex ?? this.currentStrokeIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      progress: progress ?? this.progress,
      totalStrokes: totalStrokes ?? this.totalStrokes,
    );
  }
}
