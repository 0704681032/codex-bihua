import 'package:bihua/features/detail/application/stroke_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the geometric fallback classifier (used only for chars
/// missing from the authoritative dataset). Inputs are synthetic medians
/// in the 1024-unit y-up viewBox so each case isolates one rule.
void main() {
  // Medians are stored y-up; flipYAxis=true converts to screen space.
  List<List<double>> yUp(List<List<double>> screenPoints) => [
        for (final p in screenPoints) [p[0], 1024 - p[1]],
      ];

  String classify(List<List<double>> screenPoints) =>
      StrokeClassifier.classify(medianPoints: yUp(screenPoints), flipYAxis: true);

  group('single-run strokes', () {
    test('horizontal sweep', () {
      expect(classify([[100, 300], [500, 295], [900, 300]]), '横');
    });

    test('vertical drop', () {
      expect(classify([[500, 100], [505, 500], [500, 900]]), '竖');
    });

    test('short right-down dot', () {
      expect(
        classify([
          [400, 200],
          [440, 240],
          [480, 290],
        ]),
        '点',
      );
    });

    test('long right-down diagonal is a 捺', () {
      expect(
        classify([
          [200, 150],
          [450, 400],
          [700, 680],
          [850, 850],
        ]),
        '捺',
      );
    });

    test('left-down diagonal is a 撇', () {
      expect(
        classify([
          [700, 120],
          [560, 350],
          [380, 620],
          [250, 860],
        ]),
        '撇',
      );
    });

    test('vertical with end flick is a 竖钩', () {
      expect(
        classify([
          [500, 100],
          [498, 420],
          [500, 760],
          [480, 806],
          [452, 788],
        ]),
        '竖钩',
      );
    });

    test('left-bulging near-vertical stroke is a 竖撇', () {
      expect(
        classify([
          [600, 100],
          [585, 320],
          [545, 560],
          [480, 790],
          [420, 880],
        ]),
        '撇',
      );
    });

    test('flat hugging single-run hook is a 卧钩', () {
      expect(
        classify([
          [220, 330],
          [330, 435],
          [480, 505],
          [640, 520],
          [790, 470],
          [852, 415],
        ]),
        '卧钩',
      );
    });
  });

  group('multi-run strokes', () {
    test('sharp L-bend is a 横折', () {
      expect(
        classify([
          [150, 200],
          [550, 205],
          [820, 210],
          [830, 340],
          [825, 520],
          [830, 720],
        ]),
        '横折',
      );
    });

    test('rounded down-then-right bend without hook is a 竖弯', () {
      expect(
        classify([
          [400, 100],
          [398, 260],
          [410, 430],
          [470, 560],
          [580, 650],
          [720, 690],
          [860, 700],
        ]),
        '竖弯',
      );
    });

    test('down-right-right with end flick is a 竖弯钩', () {
      expect(
        classify([
          [400, 100],
          [398, 280],
          [420, 470],
          [500, 600],
          [660, 668],
          [800, 682],
          [862, 655],
        ]),
        '竖弯钩',
      );
    });

    test('flat hugging hook is a 卧钩', () {
      expect(
        classify([
          [220, 330],
          [330, 435],
          [480, 505],
          [640, 520],
          [790, 470],
          [852, 415],
        ]),
        '卧钩',
      );
    });
  });

  group('refineName', () {
    List<double> p(int x, int y) => [x.toDouble(), (1024 - y).toDouble()];

    test('keeps plain names untouched', () {
      final resolved = StrokeClassifier.refineName(
        '竖钩',
        medianPoints: [p(500, 100), p(500, 800)],
        flipYAxis: true,
      );
      expect(resolved, '竖钩');
    });

    test('short steep tail after 横 resolves to 横钩', () {
      final resolved = StrokeClassifier.refineName(
        '横撇/横钩',
        medianPoints: [
          [p(120, 300), p(500, 305), p(860, 300)],
          [p(865, 315), p(850, 360), p(800, 390)],
        ].expand((e) => e).toList(),
        flipYAxis: true,
      );
      expect(resolved, '横钩');
    });

    test('long second sweep after 横 resolves to 横撇', () {
      final resolved = StrokeClassifier.refineName(
        '横撇/横钩',
        medianPoints: [
          [p(150, 250), p(500, 255), p(800, 250)],
          [p(795, 270), p(650, 470), p(470, 690), p(330, 860)],
        ].expand((e) => e).toList(),
        flipYAxis: true,
      );
      expect(resolved, '横撇');
    });
  });
}
