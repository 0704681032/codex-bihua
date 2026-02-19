import 'package:bihua/features/detail/application/stroke_player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next/previous and play controls update state correctly', () async {
    final controller = StrokePlayerController(totalStrokes: 3);

    expect(controller.state.currentStrokeIndex, 0);
    expect(controller.state.isPlaying, false);

    controller.nextStroke();
    expect(controller.state.currentStrokeIndex, 1);

    controller.previousStroke();
    expect(controller.state.currentStrokeIndex, 0);

    controller.togglePlay();
    expect(controller.state.isPlaying, true);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(controller.state.progress > 0, true);

    controller.pause();
    expect(controller.state.isPlaying, false);

    controller.dispose();
  });
}
