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
    expect(controller.state.progress > 0, true);

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
}
