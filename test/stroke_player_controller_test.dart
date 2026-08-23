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
