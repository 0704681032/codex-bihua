import 'package:bihua/features/detail/application/stroke_player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next/previous and play controls update state correctly', () async {
    final controller = StrokePlayerController(totalStrokes: 3);

    expect(controller.state.currentStrokeIndex, 3);
    expect(controller.state.isPlaying, false);
    expect(controller.state.progress, 1);

    controller.nextStroke();
    expect(controller.state.currentStrokeIndex, 3);
    expect(controller.state.progress, 1);

    controller.togglePlay();
    expect(controller.state.currentStrokeIndex, 0);
    expect(controller.state.isPlaying, true);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    // Must exceed the 0.01 reseed value: real timer ticks have to move
    // the drawing, not just leave the seed in place.
    expect(controller.state.progress > 0.03, true,
        reason: 'real-time ticks must advance playback');

    controller.pause();
    expect(controller.state.isPlaying, false);

    controller.previousStroke();
    expect(controller.state.currentStrokeIndex >= 0, true);

    controller.dispose();
  });

  test('advancing to the next stroke never carries over progress', () {
    final controller = StrokePlayerController(totalStrokes: 4)
      ..setSpeed(2.5) // large steps make any carry-over obvious
      ..togglePlay();

    var observedTransitions = 0;
    var previousIndex = controller.state.currentStrokeIndex;

    // Drive enough ticks to walk through every stroke deterministically.
    for (var i = 0; i < 400 && observedTransitions < 3; i += 1) {
      controller.advanceTick();
      if (controller.state.currentStrokeIndex != previousIndex) {
        // The new stroke must start from the very beginning; a carried-over
        // overshoot would make it appear partially drawn in one jump.
        expect(
          controller.state.progress,
          lessThanOrEqualTo(0.04),
          reason: 'stroke ${controller.state.currentStrokeIndex} started at '
              '${controller.state.progress}',
        );
        previousIndex = controller.state.currentStrokeIndex;
        observedTransitions += 1;
      }
    }

    expect(observedTransitions, 3);
    controller.dispose();
  });

  test('shorter strokes finish in proportionally fewer ticks', () {
    // Stroke 1 is a full-length sweep, stroke 2 a short dot.
    final controller = StrokePlayerController(
      totalStrokes: 2,
      strokeWeights: const <double>[1.0, 0.3],
    )..togglePlay();

    var ticksOnFirstStroke = 0;
    var ticksOnSecondStroke = 0;
    for (var i = 0; i < 400; i += 1) {
      if (controller.state.completed) {
        break;
      }
      controller.advanceTick();
      if (controller.state.currentStrokeIndex == 0) {
        ticksOnFirstStroke += 1;
      } else {
        ticksOnSecondStroke += 1;
      }
    }

    expect(controller.state.completed, true);
    expect(ticksOnFirstStroke, greaterThan(0));
    expect(ticksOnSecondStroke, greaterThan(0));
    // Weight 0.3 means roughly a third of the duration; allow slack for
    // tick quantization but the speedup must be clearly visible.
    expect(
      ticksOnSecondStroke,
      lessThan(ticksOnFirstStroke * 0.7),
      reason: 'dot strokes must animate faster than long sweeps',
    );
    controller.dispose();
  });

  test('missing weights keep uniform timing for every stroke', () {
    final controller = StrokePlayerController(totalStrokes: 2)..togglePlay();

    var first = 0;
    var second = 0;
    for (var i = 0; i < 400 && !controller.state.completed; i += 1) {
      controller.advanceTick();
      if (controller.state.currentStrokeIndex == 0) {
        first += 1;
      } else {
        second += 1;
      }
    }

    final ratio = first / second;
    expect(ratio, inExclusiveRange(0.6, 1.6));
    controller.dispose();
  });

  test('playback completes and stays on the finished glyph', () {
    final controller = StrokePlayerController(totalStrokes: 2)..togglePlay();

    for (var i = 0; i < 200; i += 1) {
      controller.advanceTick();
    }

    expect(controller.state.completed, true);
    expect(controller.state.isPlaying, false);
    expect(controller.state.progress, 1);

    // Restarting from the completed state rewinds to stroke 1.
    controller.togglePlay();
    expect(controller.state.currentStrokeIndex, 0);
    expect(controller.state.isPlaying, true);

    controller.dispose();
  });

  test('a throttled callback never jumps the drawing more than one frame', () {
    // Chrome throttles background tabs to ~1 timer/s; on return the
    // queued callback must not replay the whole stall at once.
    final controller = StrokePlayerController(totalStrokes: 1)
      ..setSpeed(3.2) // worst case: fastest advertised speed
      ..togglePlay();

    final startProgress = controller.state.progress;
    controller.advanceSeconds(5.0); // 5s of missed wall time in one frame

    expect(controller.state.completed, false);
    // Max single-frame delta is 0.1s of drawing.
    expect(controller.state.progress,
        lessThanOrEqualTo(startProgress + 0.1 * 3.2 + 1e-9));
    controller.dispose();
  });

  test('back-to-back queued ticks advance by wall time, not per callback',
      () {
    final controller = StrokePlayerController(totalStrokes: 1)
      ..setSpeed(1.0)
      ..togglePlay();

    for (var i = 0; i < 10; i += 1) {
      // Ten callbacks delivered back-to-back, each covering ~16ms of
      // real time: total drawn must be ~160ms, not more.
      controller.advanceSeconds(0.016);
    }

    expect(controller.state.progress, closeTo(0.16, 0.02));
    controller.dispose();
  });

  test('resuming after a pause does not fast-forward through the pause', () {
    final controller = StrokePlayerController(totalStrokes: 2)
      ..togglePlay()
      ..advanceSeconds(0.05)
      ..pause();

    final pausedProgress = controller.state.progress;

    controller.togglePlay();
    controller.advanceSeconds(0.016);

    // One nominal tick past resume — not the pause duration + tick.
    expect(
      controller.state.progress,
      closeTo(pausedProgress + 0.016, 0.004),
    );
    controller.dispose();
  });
}
