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
    // A fresh Stopwatch measures nothing until started; without this the
    // wall clock reads 0 forever and playback never advances.
    _wallClock.start();
  }

  late final Timer _ticker;
  static const Duration _tickDuration = Duration(milliseconds: 16);
  static const double _minVisibleProgress = 0.01;
  // Matches _tickDuration; a const Duration property can't be used in
  // another const initializer.
  static const double _tickSeconds = 0.016;

  // Wall clock between ticks. Advancing by measured time instead of a
  // fixed step keeps the pace stable when the event loop stalls or
  // Chrome throttles timers and then delivers queued ticks back to
  // back — fixed steps would replay every missed tick at full speed,
  // making the animation suddenly lurch forward.
  final Stopwatch _wallClock = Stopwatch();

  // Upper bound for one tick's delta. Without it, returning from a
  // backgrounded tab (timers throttled to ~1/s) would jump the drawing
  // ahead by seconds in a single frame.
  static const double _maxTickSeconds = 0.1;

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

  /// 跳到第 [index] 笔并完整显示（点击笔顺表某笔时使用），
  /// 语义与 nextStroke/previousStroke 一致：跳转即暂停。
  void jumpToStroke(int index) {
    if (state.totalStrokes == 0) {
      return;
    }
    final clamped = index.clamp(0, state.totalStrokes - 1);
    state = state.copyWith(
      currentStrokeIndex: clamped,
      progress: 1,
      isPlaying: false,
    );
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
    // Upper bound stays above the 快速 chip preset (2.0) so the
    // advertised speed is actually reachable and the chip shows selected.
    final normalized = speed.clamp(0.3, 3.2).toDouble();
    state = state.copyWith(speed: normalized);
  }

  void _onTick(Timer timer) {
    final elapsed = _wallClock.elapsedMilliseconds;
    _wallClock.reset();
    // Reset even while paused so resuming never replays the pause as a
    // giant first delta.
    if (!state.isPlaying || elapsed <= 0) {
      return;
    }
    _advance(elapsed / 1000);
  }

  /// Advances the animation by one nominal 16ms tick. Exposed for tests
  /// so the stroke-advance behavior can be verified without real timers.
  @visibleForTesting
  void advanceTick() {
    _advance(_tickSeconds);
  }

  /// Advances the animation by [seconds] of wall time. Exposed for tests
  /// so stall/throttle bursts can be simulated deterministically.
  @visibleForTesting
  void advanceSeconds(double seconds) {
    _advance(seconds);
  }

  void _advance(double rawDeltaSeconds) {
    if (!state.isPlaying || state.totalStrokes == 0) {
      return;
    }

    if (state.completed) {
      state = state.copyWith(isPlaying: false);
      return;
    }

    // Single choke point for the stall guard: however much wall time a
    // callback missed, one frame may never draw more than this fraction,
    // so queued/throttled ticks cannot lurch the animation forward.
    final deltaSeconds =
        rawDeltaSeconds.clamp(0.0, _maxTickSeconds).toDouble();

    // Longer strokes take longer: the tick increment is scaled by the
    // stroke's relative length (weight 1 = longest stroke, smaller =
    // faster), so a 点 sweeps by quickly while a long 横 keeps a natural
    // pace. Missing weights fall back to uniform timing.
    final weight = state.weightAt(state.currentStrokeIndex);
    final nextProgress =
        state.progress + deltaSeconds * state.speed / weight;
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
  return StrokePlayerController(
    totalStrokes: key.totalStrokes,
    strokeWeights: key.strokeWeights,
  );
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
