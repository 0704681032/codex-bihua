import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Path;

import 'package:bihua/features/detail/application/stroke_reveal.dart';
import 'package:bihua/features/dictionary/domain/stroke_path.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the red reveal against the "red line does not fully cover the
/// grey outline" bug.
///
/// For every sampled boundary point of a real stroke's outline there
/// must exist a brush stamp whose disk contains it. Oversized brushes
/// are safe (paint is clipped by the outline), so the only failure mode
/// is uncovered ink — exactly what users see as grey slivers.
void main() {
  final rawData = File('assets/data/chars_3500.json').readAsStringSync();
  final data = jsonDecode(rawData) as List<dynamic>;
  final byChar = <String, Map<dynamic, dynamic>>{
    for (final entry in data)
      if (entry is Map && entry['char'] is String)
        entry['char'] as String: entry,
  };

  // 样例字集: hooks, tapered diagonals, bends, enclosures.
  const sampleChars = <String>[
    '火', '大', '人', '我', '及', '乃', '字', '万',
    '方', '心', '母', '马', '水', '回', '成', '建',
  ];

  test('reveal brush covers every inked boundary point', () {
    final failures = <String>[];
    var totalPoints = 0;

    for (final char in sampleChars) {
      final entry = byChar[char];
      if (entry == null) {
        failures.add('$char 不在字库');
        continue;
      }

      for (final strokeItem in entry['strokes'] as List<dynamic>) {
        final stroke = strokeItem as Map<dynamic, dynamic>;
        final outline = parseStrokeSvg(stroke['svgPath'] as String);
        final medians = <Offset>[
          for (final p in stroke['medianPoints'] as List<dynamic>)
            Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ];
        if (medians.length < 2) {
          continue;
        }

        final strokePath = StrokePath.fromJson(
          Map<String, dynamic>.from(stroke),
        );
        final profile = StrokeReveal.computeWidthProfiles(
          <StrokePath>[strokePath],
          <Path>[outline],
        ).first;
        final stamps =
            StrokeReveal.buildBrushStamps(medians, profile);
        expect(stamps, isNotEmpty,
            reason: '$char needs brush stamps');

        var checked = 0;
        var missed = 0;
        Offset? worstPoint;
        var worstGap = 0.0;
        for (final point in _boundaryPoints(outline, step: 5)) {
          final gap = _gapToStamps(point, stamps);
          checked += 1;
          if (gap > 1.5) {
            missed += 1;
            if (gap > worstGap) {
              worstGap = gap;
              worstPoint = point;
            }
          }
        }
        totalPoints += checked;

        if (missed > 0) {
          final ratio =
              (missed / math.max(1, checked) * 100).toStringAsFixed(1);
          final gapText = worstGap.toStringAsFixed(1);
          failures.add(
              '$char 第${stroke["order"]}笔: $missed/$checked 点未覆盖 ($ratio%), '
              '最大缺口 $gapText @ $worstPoint');
        }
      }
    }

    expect(totalPoints, greaterThan(5000), reason: '样本量过小');
    if (failures.isNotEmpty) {
      fail('存在未覆盖的笔画边缘:\n${failures.take(20).join('\n')}');
    }
  });
}

// ---- helpers ----

List<Offset> _boundaryPoints(Path path, {required double step}) {
  final points = <Offset>[];
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d <= metric.length; d += step) {
      final tangent = metric.getTangentForOffset(d);
      if (tangent != null) {
        points.add(tangent.position);
      }
    }
  }
  return points;
}

/// Distance a point sits outside the union of stamp disks; 0 means
/// covered.
double _gapToStamps(Offset point, List<BrushStamp> stamps) {
  var best = double.infinity;
  for (final stamp in stamps) {
    final d = (point - stamp.center).distance - stamp.radius;
    if (d < best) {
      best = d;
    }
  }
  return best;
}
