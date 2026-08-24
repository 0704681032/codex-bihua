import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stroke_player_state.dart';

class StrokePlayerController extends StateNotifier<StrokePlayerState> {
  StrokePlayerController({
    required int totalStrokes,
    List<double> strokeWeights = const <double>[],
  }) : super(StrokePlayerState.initial(
          totalStrokes: totalStrokes,
          strokeWeights: strokeWeights,
        )) {
    _ticker = Timer.periodic(_tickDuration, _onTick);
  }

  late final Timer _ticker;
  static const Duration _tickDuration = Duration(milliseconds: 16);
  static const double _minVisibleProgress = 0.01;
  // Matches _tickDuration; a const Duration property can't be used in
  // another const initializer.
  static const double _tickSeconds = 0.016;

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
    final normalized = speed.clamp(0.3, 3.0).toDouble();
    state = state.copyWith(speed: normalized);
  }

  void _onTick(Timer timer) {
    _advance();
  }

  /// Advances the animation by one tick. Exposed for tests so the
  /// stroke-advance behavior can be verified without real timers.
  @visibleForTesting
  void advanceTick() {
    _advance();
  }

  void _advance() {
    if (!state.isPlaying || state.totalStrokes == 0) {
      return;
    }

    if (state.completed) {
      state = state.copyWith(isPlaying: false);
      return;
    }

    // Longer strokes take longer: the tick increment is scaled by the
    // stroke's relative length (weight 1 = longest stroke, smaller =
    // faster), so a 点 sweeps by quickly while a long 横 keeps a natural
    // pace. Missing weights fall back to uniform timing.
    final weight = state.weightAt(state.currentStrokeIndex);
    final nextProgress =
        state.progress + _tickSeconds * state.speed / weight;
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

    // Each stroke must animate from its very beginning: never carry the
    // previous stroke's overshoot into the next one.
    state = state.copyWith(
      currentStrokeIndex: nextIndex,
      progress: _minVisibleProgress,
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
    this.strokeWeights = const <double>[],
  });

  final String sessionId;
  final String char;
  final int totalStrokes;
  final List<double> strokeWeights;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StrokePlayerKey &&
            runtimeType == other.runtimeType &&
            sessionId == other.sessionId &&
            char == other.char &&
            totalStrokes == other.totalStrokes &&
            listEquals(strokeWeights, other.strokeWeights);
  }

  @override
  int get hashCode => Object.hash(sessionId, char, totalStrokes) ^
      Object.hashAll(strokeWeights);
}
