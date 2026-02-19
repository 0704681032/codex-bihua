import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stroke_player_state.dart';

class StrokePlayerController extends StateNotifier<StrokePlayerState> {
  StrokePlayerController({required int totalStrokes})
      : super(StrokePlayerState.initial(totalStrokes: totalStrokes)) {
    _ticker = Timer.periodic(const Duration(milliseconds: 30), _onTick);
  }

  late final Timer _ticker;
  static const double _minVisibleProgress = 0.01;

  void setTotalStrokes(int total) {
    final safe = total < 0 ? 0 : total;
    state = StrokePlayerState.initial(totalStrokes: safe);
  }

  void togglePlay() {
    if (state.totalStrokes == 0) {
      return;
    }

    if (state.isPlaying) {
      pause();
      return;
    }

    if (state.completed) {
      state = state.copyWith(
        currentStrokeIndex: 0,
        progress: _minVisibleProgress,
        isPlaying: true,
      );
      return;
    }

    state = state.copyWith(isPlaying: true);
  }

  void pause() {
    state = state.copyWith(isPlaying: false);
  }

  void nextStroke() {
    if (state.totalStrokes == 0) {
      return;
    }

    // Keep stepping deterministic: one tap moves to the next stroke and keeps it visible.
    final next = state.currentStrokeIndex + 1;
    if (next >= state.totalStrokes) {
      state = state.copyWith(
        currentStrokeIndex: state.totalStrokes,
        progress: 1,
        isPlaying: false,
      );
      return;
    }

    state = state.copyWith(
      currentStrokeIndex: next,
      progress: _minVisibleProgress,
      isPlaying: false,
    );
  }

  void previousStroke() {
    if (state.totalStrokes == 0) {
      return;
    }

    if (state.completed) {
      state = state.copyWith(
        currentStrokeIndex: state.totalStrokes - 1,
        progress: 1,
        isPlaying: false,
      );
      return;
    }

    final prev = state.currentStrokeIndex - 1;
    if (prev < 0) {
      state = state.copyWith(
        currentStrokeIndex: 0,
        progress: _minVisibleProgress,
        isPlaying: false,
      );
      return;
    }

    state = state.copyWith(
      currentStrokeIndex: prev,
      progress: 1,
      isPlaying: false,
    );
  }

  void reset() {
    state = StrokePlayerState.initial(totalStrokes: state.totalStrokes);
  }

  void setSpeed(double speed) {
    final normalized = speed.clamp(0.3, 2.5).toDouble();
    state = state.copyWith(speed: normalized);
  }

  void _onTick(Timer timer) {
    if (!state.isPlaying || state.totalStrokes == 0) {
      return;
    }

    if (state.completed) {
      state = state.copyWith(isPlaying: false);
      return;
    }

    final nextProgress = state.progress + 0.03 * state.speed;
    if (nextProgress < 1) {
      state = state.copyWith(progress: nextProgress);
      return;
    }

    final nextIndex = state.currentStrokeIndex + 1;
    if (nextIndex >= state.totalStrokes) {
      state = state.copyWith(
        currentStrokeIndex: state.totalStrokes,
        progress: 1,
        isPlaying: false,
      );
      return;
    }

    state = state.copyWith(
      currentStrokeIndex: nextIndex,
      progress: nextProgress - 1,
      isPlaying: true,
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }
}

final strokePlayerProvider = StateNotifierProvider.autoDispose
    .family<StrokePlayerController, StrokePlayerState, StrokePlayerKey>(
        (ref, key) {
  return StrokePlayerController(totalStrokes: key.totalStrokes);
});

class StrokePlayerKey {
  const StrokePlayerKey({
    required this.sessionId,
    required this.char,
    required this.totalStrokes,
  });

  final String sessionId;
  final String char;
  final int totalStrokes;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StrokePlayerKey &&
            runtimeType == other.runtimeType &&
            sessionId == other.sessionId &&
            char == other.char &&
            totalStrokes == other.totalStrokes;
  }

  @override
  int get hashCode => Object.hash(sessionId, char, totalStrokes);
}
