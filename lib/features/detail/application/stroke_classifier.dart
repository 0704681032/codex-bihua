import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset;

/// Classifies a stroke from its median polyline into standard 笔画名称
/// (横、竖、撇、点、横折钩…). Pure geometry — no widget dependencies —
/// so it can be regression-tested against official stroke sequences.
class StrokeClassifier {
  const StrokeClassifier._();

  static const double _viewBoxSize = 1024;

  /// Direction-run split thresholds.
  static const double _turnRadians = 0.7;
  static const double _minTurnSegment = 24;
  static const double _minRunLength = 30;
  static const double _dotMaxTotalLength = 280;

  /// Terminal corner sharpness separating 横钩 from 横撇 (~35°).
  static const double _sharpTailTurn = 0.61;

  /// Resolves slash-joined ambiguous names coming from the letter-coded
  /// dataset (cnchar merges pairs that share one letter, e.g.
  /// "横撇/横钩"). Geometry picks the right variant; anything it cannot
  /// distinguish falls back to the first candidate.
  static String refineName(
    String candidate, {
    required List<List<double>> medianPoints,
    required bool flipYAxis,
  }) {
    if (!candidate.contains('/')) {
      return candidate;
    }
    final options = candidate.split('/');
    final points = _toScreenPoints(medianPoints, flipYAxis);
    if (points == null || points.length < 2) {
      return options.first;
    }

    if (_samePair(options, const <String>['横撇', '横钩'])) {
      // 横钩 breaks off with a sharp terminal corner; 横撇 keeps
      // curving smoothly through its tip. Calibrated on real medians:
      // hooks peak around 40-60° in the last section while 撇 tips stay
      // under ~25° (the 横-to-tail corner itself sits before the cutoff
      // and must not leak into the measurement).
      final densified = _densify(points, 26);
      return _maxTurnInTail(densified) >= _sharpTailTurn ? '横钩' : '横撇';
    }

    if (_samePair(options, const <String>['斜钩', '卧钩'])) {
      final net = points.last - points.first;
      return net.dx.abs() > net.dy.abs() * 1.15 ? '卧钩' : '斜钩';
    }

    // Remaining merged pairs (横折折/横折弯, 竖折折/竖折撇,
    // 横折折折钩/横撇弯钩) are near-indistinguishable in median data —
    // keep the first (more common) name.
    return options.first;
  }

  static bool _samePair(List<String> options, List<String> pair) {
    return options.length == 2 &&
        options[0] == pair[0] &&
        options[1] == pair[1];
  }

  /// Resamples the polyline at roughly even [step] spacing so per-sample
  /// turn measurements do not depend on the source's sample density.
  static List<Offset> _densify(List<Offset> points, double step) {
    if (points.length < 2) {
      return points;
    }
    final result = <Offset>[points.first];
    var carried = 0.0;
    for (var i = 0; i + 1 < points.length; i += 1) {
      final a = points[i];
      final b = points[i + 1];
      final segLength = (b - a).distance;
      if (segLength == 0) {
        continue;
      }
      final direction = (b - a) / segLength;
      var travelled = step - carried;
      while (travelled < segLength) {
        result.add(a + direction * travelled);
        travelled += step;
      }
      carried = segLength - (travelled - step);
    }
    result.add(points.last);
    return result;
  }

  /// Largest direction change between consecutive samples after 58% of
  /// the polyline, in radians. Sharp calligraphic corners (钩) turn hard
  /// right at the tip; smooth sweeps (撇) spread the turning out.
  static double _maxTurnInTail(List<Offset> points) {
    if (points.length < 4) {
      return 0;
    }
    var maxTurn = 0.0;
    // Ceil keeps the mid-stroke 横-to-tail corner out of the window even
    // for very short medians (calibrated on 字's 8-sample strokes).
    final start = (points.length * 0.58).ceil();
    for (var i = start; i + 2 < points.length; i += 1) {
      final turn = _angleBetween(points[i], points[i + 1], points[i + 2]);
      if (turn > maxTurn) {
        maxTurn = turn;
      }
    }
    return maxTurn;
  }

  static String classify({
    required List<List<double>> medianPoints,
    required bool flipYAxis,
    String fallback = '待识别',
  }) {
    final points = _toScreenPoints(medianPoints, flipYAxis);
    if (points == null) {
      return fallback;
    }
    final total = _polylineLength(points);
    if (total <= 0) {
      return fallback;
    }

    final runs = _runsOf(points);
    if (runs.isEmpty) {
      return total < _dotMaxTotalLength ? '点' : fallback;
    }

    if (runs.length == 1 && runs.first.length == points.length) {
      return _classifySingleRun(points, total);
    }

    final names = <String>[for (final run in runs) _segmentName(run)];
    return _combineRuns(names, runs, points, total);
  }

  // ---- single continuous run (no sharp direction change) ----

  static String _classifySingleRun(List<Offset> points, double total) {
    final name = _segmentName(points);

    if (_endsWithUpwardFlick(points)) {
      // A lone downward sweep that flicks up at the tip is a hook.
      if (name == '竖') {
        return '竖钩';
      }
      if (name == '捺') {
        final net = points.last - points.first;
        final flatHugger = net.dx.abs() > net.dy.abs() * 1.15;
        if (!flatHugger && _isRoundedVerticalBend(points)) {
          // Rounded sweep that ends in an up-flick (乚).
          return '竖弯钩';
        }
        return flatHugger ? '卧钩' : '斜钩';
      }
      if (name == '横' && total > 350) {
        // Flat hugging hook that starts by dipping down (心's ㇃).
        final initial = _averageDirection(points, fromStart: true);
        if (initial.dy > 40) {
          return '卧钩';
        }
      }
    }

    switch (name) {
      case '点':
        return '点';
      case '捺':
        // A rounded 竖弯 (四's legs, 乚 without hook) reads as a diagonal
        // net: steep at the start, flat to the right at the end.
        if (_isRoundedVerticalBend(points)) {
          return '竖弯';
        }
        return total < _dotMaxTotalLength ? '点' : '捺';
      case '竖':
        // A near-vertical stroke bulging left along its whole length is
        // the calligraphic 竖撇 (月's first two strokes), not a straight
        // 竖.
        if (total > 250 && _bulgesLeft(points)) {
          return '撇';
        }
        return '竖';
      default:
        return name;
    }
  }

  /// True when the polyline starts moving mostly down and ends moving
  /// mostly right with a gentle distributed turn between the two — the
  /// signature of 竖弯 as opposed to the sharp-cornered 竖折.
  static bool _isRoundedVerticalBend(List<Offset> points) {
    final initial = _averageDirection(points, fromStart: true);
    final finalDir = _averageDirection(points, fromStart: false);
    return initial.dy > initial.dx.abs() * 1.6 &&
        initial.dy > 0 &&
        finalDir.dx > finalDir.dy.abs() * 1.6 &&
        finalDir.dx > 0;
  }

  /// Average direction over the first/last third of the polyline.
  static Offset _averageDirection(List<Offset> points,
      {required bool fromStart}) {
    final span = math.max(1, (points.length / 3).floor());
    if (fromStart) {
      return points[span] - points.first;
    }
    return points.last - points[points.length - 1 - span];
  }

  /// Signed lateral drift of the samples relative to the chord. Positive
  /// values mean the path bows toward the left of the writing direction
  /// (screen coordinates) — how 撇 curves away from a straight 竖.
  static bool _bulgesLeft(List<Offset> points) {
    final chord = points.last - points.first;
    final length = chord.distance;
    if (length == 0) {
      return false;
    }
    var sum = 0.0;
    for (var i = 1; i < points.length - 1; i += 1) {
      final rel = points[i] - points.first;
      sum += (chord.dx * rel.dy - chord.dy * rel.dx) / length;
    }
    final mean = sum / math.max(1, points.length - 2);
    // Screen coordinates are y-down with a left-handed cross product:
    // for a downward chord, samples bulging toward screen-left (how 撇
    // curves away from a straight 竖) produce negative lateral offsets.
    return chord.dy > 0 ? mean < -12 : mean > 12;
  }

  // ---- multi-run combination ----

  static String _combineRuns(
    List<String> names,
    List<List<Offset>> runs,
    List<Offset> allPoints,
    double total,
  ) {
    final first = names.first;
    final second = names.length > 1 ? names[1] : '';
    final hasHook = _endsWithUpwardFlick(allPoints);
    final tailRatio =
        _polylineLength(runs.last) / math.max(1e-6, total);

    if (first == '横') {
      switch (second) {
        case '竖':
          return hasHook ? '横折钩' : '横折';
        case '竖钩':
          return '横折钩';
        case '撇':
        case '平撇':
          // 横钩 (宀's ㇖): a short steep tail flicking off a long 横.
          // A full second stroke means 横撇 instead (又).
          if (tailRatio < 0.45) {
            return '横钩';
          }
          return hasHook ? '横折钩' : '横撇';
        case '捺':
          return '横折';
      }
      if (names.length >= 4) {
        if (_namesMatch(names, const <String>['横', '竖', '横', '撇'])) {
          return '横折折撇';
        }
        if (_namesMatch(names, const <String>['横', '竖', '横', '竖'])) {
          return hasHook ? '横折折折钩' : '横折折';
        }
      }
    }

    if (first == '竖') {
      if (second == '横' || second == '提') {
        if (hasHook) {
          return '竖弯钩';
        }
        if (second == '提') {
          return '竖提';
        }
        // A gentle joint means a rounded bend (竖弯); a hard corner is
        // the classic 竖折 (山).
        return _jointIsSharp(runs[0], runs[1]) ? '竖折' : '竖弯';
      }
      if (second == '竖钩') {
        return '竖钩';
      }
      if (names.length >= 3 &&
          _namesMatch(names, const <String>['竖', '横', '竖'])) {
        return hasHook ? '竖折折钩' : '竖折折';
      }
    }

    if (first == '撇') {
      if (second == '横' || second == '提') {
        return '撇折';
      }
      if (second == '点' || second == '捺') {
        return '撇点';
      }
    }

    if (first == '捺') {
      // 斜钩 (戈/我): long diagonal down-right with an up-flick tip.
      // 卧钩 (心): flatter, hugging the baseline.
      if (hasHook || second == '平撇') {
        final net = allPoints.last - allPoints.first;
        return net.dx.abs() > net.dy.abs() * 1.15 ? '卧钩' : '斜钩';
      }
    }

    if (hasHook && second == '平撇') {
      // A vertical body whose only extra run is the tiny terminal flick
      // (亅): the splitter sees a stubby up-left tail after the shaft.
      if (first == '竖') {
        return '竖钩';
      }
    }

    return '$first$second';
  }

  static bool _namesMatch(List<String> names, List<String> pattern) {
    if (names.length < pattern.length) {
      return false;
    }
    for (var i = 0; i < pattern.length; i += 1) {
      if (names[i] != pattern[i]) {
        return false;
      }
    }
    return true;
  }

  /// Interior angle at the junction of two runs: small angle (sharp
  /// corner) → 折, wide angle (smooth curve) → 弯.
  static bool _jointIsSharp(List<Offset> before, List<Offset> after) {
    final inDir = before.last - before[math.max(0, before.length - 2)];
    final outDir = after.length > 1 ? after[1] - after.first : after.last;
    final lu = inDir.distance;
    final lv = outDir.distance;
    if (lu == 0 || lv == 0) {
      return true;
    }
    final cos = (inDir.dx * outDir.dx + inDir.dy * outDir.dy) / (lu * lv);
    final turn = math.acos(cos.clamp(-1.0, 1.0));
    // Interior angle ≈ 180° - turn; sharp corners keep a large turn.
    return turn > 1.1;
  }

  // ---- shared geometry helpers ----

  /// Converts raw median samples into screen-space points (the asset
  /// data is y-up, the classifier reasons in what the user sees).
  static List<Offset>? _toScreenPoints(
    List<List<double>> medianPoints,
    bool flipYAxis,
  ) {
    final raw = medianPoints
        .where((p) => p.length >= 2)
        .map((p) => Offset(p[0], p[1]))
        .toList(growable: false);
    if (raw.length < 2) {
      return null;
    }
    if (!flipYAxis) {
      return raw;
    }
    return <Offset>[
      for (final p in raw) Offset(p.dx, _viewBoxSize - p.dy),
    ];
  }

  /// Direction runs with insignificant wobble filtered out.
  static List<List<Offset>> _runsOf(List<Offset> points) {
    return _splitIntoRuns(points)
        .where((run) => _polylineLength(run) > _minRunLength)
        .toList(growable: false);
  }

  static String _segmentName(List<Offset> segment) {
    final start = segment.first;
    final end = segment.last;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final absDx = dx.abs();
    final absDy = dy.abs();

    if (absDx > absDy * 2.2) {
      return dx > 0 ? '横' : '提';
    }
    if (absDy > absDx * 2.2) {
      return dy > 0 ? '竖' : '提';
    }
    if (dy > 0) {
      return dx > 0 ? '捺' : '撇';
    }
    return dx > 0 ? '提' : '平撇';
  }

  static double _polylineLength(List<Offset> points) {
    var sum = 0.0;
    for (var i = 0; i + 1 < points.length; i += 1) {
      sum += (points[i + 1] - points[i]).distance;
    }
    return sum;
  }

  /// Splits the polyline at direction changes larger than ~40 degrees,
  /// merging tiny wobble into the surrounding run.
  static List<List<Offset>> _splitIntoRuns(List<Offset> points) {
    final runs = <List<Offset>>[
      <Offset>[points.first],
    ];

    for (var i = 1; i < points.length - 1; i += 1) {
      final prev = points[i - 1];
      final cur = points[i];
      final next = points[i + 1];
      final turn = _angleBetween(prev, cur, next);
      if (turn > _turnRadians &&
          (cur - prev).distance > _minTurnSegment) {
        runs.add(<Offset>[cur]);
      } else {
        runs.last.add(cur);
      }
    }
    runs.last.add(points.last);
    return runs;
  }

  static double _angleBetween(Offset a, Offset b, Offset c) {
    final u = b - a;
    final v = c - b;
    final lu = u.distance;
    final lv = v.distance;
    if (lu == 0 || lv == 0) {
      return 0;
    }
    final cos = (u.dx * v.dx + u.dy * v.dy) / (lu * lv);
    return math.acos(cos.clamp(-1.0, 1.0).toDouble());
  }

  /// True when the stroke ends with a genuine upward reversal — the tip
  /// climbs while the flow just before it was still descending (the hook
  /// at the end of 竖钩/横折钩/斜钩 style strokes). A plain downward
  /// stroke never triggers this: every scanned gap must actively rise.
  static bool _endsWithUpwardFlick(List<Offset> points) {
    if (points.length < 3) {
      return false;
    }

    var i = points.length - 1;
    var rise = 0.0;
    while (i > 0) {
      final gap = points[i - 1].dy - points[i].dy; // >0 = climbed
      if (gap <= 1) {
        break;
      }
      rise += gap;
      i -= 1;
    }
    // No real climbing streak (or it spans the whole stroke, i.e. a 提).
    if (rise < 14 || i == points.length - 1 || i == 0) {
      return false;
    }
    // The stroke must descend into the hook's bottom...
    if (points[i].dy - points[i - 1].dy < 6) {
      return false;
    }
    // ...and the overall flow must come from above (writing moves down).
    final mid = points[points.length >> 1];
    return mid.dy - points.first.dy > 25;
  }
}
