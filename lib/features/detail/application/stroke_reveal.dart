import 'dart:math' as math;
import 'dart:ui' show Path;

import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails;
import 'package:flutter/material.dart' show Offset, Rect;
import 'package:path_drawing/path_drawing.dart';

import '../../dictionary/domain/stroke_path.dart';

/// One circular footprint of the animated reveal brush.
class BrushStamp {
  const BrushStamp(this.center, this.radius);

  final Offset center;
  final double radius;
}

/// Geometry behind the red "current stroke" reveal.
///
/// Real glyph data stores closed filled outlines, so a partial extraction
/// of the outline would reveal nothing meaningful. Instead the full
/// outline is clipped by a brush swept along the stroke median: the brush
/// radius follows the local stroke width so tapered strokes (撇/捺) are
/// revealed exactly to their edges.
///
/// Everything here is pure computation so the *coverage* guarantee —
/// every inked boundary point lies inside some stamp — can be tested
/// directly against real character data.
class StrokeReveal {
  const StrokeReveal._();

  /// Measures the local half-width of every stroke along its median so
  /// the reveal brush can follow the outline's true shape. Real glyph
  /// strokes taper (撇 thins towards the tip, 捺 widens), so a single
  /// brush radius cannot cover them.
  ///
  /// For each median sample the width is measured with two rays cast
  /// perpendicular to the writing direction. Overshooting is safe: the
  /// painted red is clipped by the outline itself.
  static List<List<double>> computeWidthProfiles(
    List<StrokePath> strokes,
    List<Path> outlines,
  ) {
    final profiles = <List<double>>[];
    for (var i = 0; i < strokes.length; i += 1) {
      final medians = _medianPointsOf(strokes[i]);
      if (medians == null || i >= outlines.length) {
        profiles.add(const <double>[]);
        continue;
      }
      final segments = _outlineSegments(outlines[i]);
      if (segments.isEmpty) {
        profiles.add(const <double>[]);
        continue;
      }

      final profile = <double>[];
      for (var j = 0; j < medians.length; j += 1) {
        final normal = _localNormal(medians, j);
        final forward = _rayCast(medians[j], normal, segments);
        final backward = _rayCast(medians[j], -normal, segments);

        double width;
        if (forward > 0 && backward > 0) {
          width = forward + backward;
        } else {
          // Degenerate ray (open/synthetic path) — fall back to twice
          // the nearest-edge distance.
          width = 2 * _minDistance(medians[j], segments);
        }
        profile.add((width * 0.5 * 1.28 + 2).clamp(6.0, 110.0).toDouble());
      }
      profiles.add(profile);
    }
    return profiles;
  }

  /// Builds the ordered brush footprints covering [progress] of the
  /// stroke. Oversized relative to the measured widths on purpose: an
  /// oversized brush cannot bleed outside the outline (the paint is
  /// clipped by it), while an undersized one leaves grey slivers — the
  /// visible bug this module exists to prevent.
  static List<BrushStamp> buildBrushStamps(
    List<Offset> rawMedian,
    List<double> profile,
  ) {
    if (rawMedian.length < 2) {
      return const <BrushStamp>[];
    }

    final resampled = _resampleWithRadii(rawMedian, profile, step: 7);
    final points = resampled.$1;
    var radii = resampled.$2;

    // Generosity factor on top of the measured half-widths.
    radii = <double>[
      for (final r in radii) (r * 1.22 + 4).clamp(8.0, 170.0),
    ];

    final smoothed = _smoothWithWidth(points, radii);

    final stamps = <BrushStamp>[
      for (var i = 0; i < smoothed.$1.length; i += 1)
        BrushStamp(smoothed.$1[i], smoothed.$2[i]),
    ];

    // Tapered tips usually extend past the last median sample; extend
    // the brush a little beyond both ends so the extremes stay covered.
    _extendEnd(stamps, forward: false);
    _extendEnd(stamps, forward: true);
    return stamps;
  }

  /// The region swept by the brush up to [progress] of the median
  /// length, as a single path (union of stamped circles).
  static Path sweptCapsule(List<BrushStamp> stamps, double progress) {
    final sweep = Path();
    if (stamps.isEmpty) {
      return sweep;
    }
    final clamped = progress.clamp(0.0, 1.0);

    void stampAt(Offset center, double radius) {
      sweep.addOval(
          Rect.fromCircle(center: center, radius: math.max(radius, 0.5)));
    }

    stampAt(stamps.first.center, stamps.first.radius);
    if (clamped <= 0) {
      return sweep;
    }

    var travelled = 0.0;
    final total = _stampsLength(stamps);
    final target = total * clamped;

    for (var i = 0; i + 1 < stamps.length; i += 1) {
      final a = stamps[i];
      final b = stamps[i + 1];
      final segLength = (b.center - a.center).distance;
      if (segLength <= 0) {
        continue;
      }
      if (travelled + segLength > target) {
        final t = ((target - travelled) / segLength).clamp(0.0, 1.0);
        stampAt(
          a.center + (b.center - a.center) * t,
          a.radius + (b.radius - a.radius) * t,
        );
        return sweep;
      }

      // Densify long hops so consecutive circles always overlap.
      final direction = (b.center - a.center) / segLength;
      final step = math.max(a.radius * 0.45, 1.5);
      final count = (segLength / step).ceil();
      for (var k = 1; k <= count; k += 1) {
        final t = k / count;
        stampAt(
          a.center + direction * (segLength * t),
          a.radius + (b.radius - a.radius) * t,
        );
      }
      travelled += segLength;
      if (travelled >= target) {
        return sweep;
      }
    }
    return sweep;
  }

  // ---- internals ----

  /// Even-spacing resample of the median with linearly interpolated
  /// radii, so downstream smoothing/stamping behaves uniformly across
  /// characters regardless of source sample density.
  static (List<Offset>, List<double>) _resampleWithRadii(
    List<Offset> source,
    List<double> profile,
    {required double step}
  ) {
    double radiusAt(int index) =>
        index >= 0 && index < profile.length ? profile[index] : 24;

    final points = <Offset>[source.first];
    final radii = <double>[radiusAt(0)];

    var carried = 0.0;
    for (var i = 0; i + 1 < source.length; i += 1) {
      final a = source[i];
      final b = source[i + 1];
      final segLength = (b - a).distance;
      if (segLength == 0) {
        continue;
      }
      final direction = (b - a) / segLength;
      var travelled = step - carried;
      while (travelled < segLength) {
        points.add(a + direction * travelled);
        final t = travelled / segLength;
        radii.add(radiusAt(i) + (radiusAt(i + 1) - radiusAt(i)) * t);
        travelled += step;
      }
      carried = segLength - (travelled - step);
    }

    points.add(source.last);
    radii.add(radiusAt(profile.length - 1));
    return (points, radii);
  }

  /// Chaikin-style corner cutting applied to (point, radius) pairs:
  /// rounds the sharp joints of the median polyline so the animated pen
  /// path bends naturally, while interpolating the brush width along the
  /// way. Endpoints are preserved exactly.
  static (List<Offset>, List<double>) _smoothWithWidth(
    List<Offset> input,
    List<double> profile,
  ) {
    if (input.length < 3) {
      return (input, profile);
    }
    final points = <Offset>[input.first];
    final radii = <double>[profile.first];

    for (var i = 0; i < input.length - 1; i += 1) {
      final a = input[i];
      final b = input[i + 1];
      final ra = profile[i];
      final rb = profile[i + 1];
      points.add(a + (b - a) * 0.25);
      radii.add(ra + (rb - ra) * 0.25);
      points.add(a + (b - a) * 0.75);
      radii.add(ra + (rb - ra) * 0.75);
    }
    points.add(input.last);
    radii.add(profile.last);
    return (points, radii);
  }

  /// Adds one extra stamp beyond the first/last point, following the end
  /// tangent, to cover tapered tips that reach past the median.
  static void _extendEnd(List<BrushStamp> stamps, {required bool forward}) {
    if (stamps.length < 2) {
      return;
    }
    final index = forward ? stamps.length - 1 : 0;
    final inner = forward ? stamps.length - 2 : 1;
    final tip = stamps[index];
    final prev = stamps[inner];
    var direction = tip.center - prev.center;
    final length = direction.distance;
    if (length == 0) {
      return;
    }
    direction /= length;
    stamps.insert(
      forward ? stamps.length : 0,
      BrushStamp(
          tip.center + direction * tip.radius * 0.55, tip.radius * 1.3),
    );
  }

  static double _stampsLength(List<BrushStamp> stamps) {
    var sum = 0.0;
    for (var i = 0; i + 1 < stamps.length; i += 1) {
      sum += (stamps[i + 1].center - stamps[i].center).distance;
    }
    return sum;
  }

  static List<Offset>? _medianPointsOf(StrokePath stroke) {
    final points = stroke.medianPoints
        .where((p) => p.length >= 2)
        .map((p) => Offset(p[0], p[1]))
        .toList(growable: false);
    if (points.length < 2) {
      return null;
    }
    return points;
  }

  /// Unit vector perpendicular to the median's writing direction at
  /// [index].
  static Offset _localNormal(List<Offset> points, int index) {
    final a = points[math.max(0, index - 1)];
    final b = points[math.min(points.length - 1, index + 1)];
    final dir = b - a;
    final len = dir.distance;
    if (len == 0) {
      return const Offset(0, 1);
    }
    return Offset(-dir.dy / len, dir.dx / len);
  }

  /// Flattens the outline into segments, closing each contour so rays
  /// hit the start cap as well.
  static List<(Offset, Offset)> _outlineSegments(Path path,
      {double step = 8}) {
    final segments = <(Offset, Offset)>[];
    for (final metric in path.computeMetrics()) {
      Offset? previous;
      for (var d = 0.0; d <= metric.length + step; d += step) {
        final tangent =
            metric.getTangentForOffset(math.min(d, metric.length));
        if (tangent == null) {
          continue;
        }
        final current = tangent.position;
        if (previous != null) {
          segments.add((previous, current));
        }
        previous = current;
      }
      if (previous != null) {
        final first = metric.getTangentForOffset(0)?.position ?? previous;
        if ((first - previous).distance > 0.5) {
          segments.add((previous, first));
        }
      }
    }
    return segments;
  }

  /// Smallest positive intersection distance of the ray
  /// [origin] + t·[direction] (t > 0) with any outline segment.
  static double _rayCast(
    Offset origin,
    Offset direction,
    List<(Offset, Offset)> segments,
  ) {
    var best = 0.0;
    for (final (a, b) in segments) {
      final edge = b - a;
      final denom = direction.dx * edge.dy - direction.dy * edge.dx;
      if (denom.abs() < 1e-9) {
        continue;
      }
      final toA = a - origin;
      final t = (toA.dx * edge.dy - toA.dy * edge.dx) / denom;
      final s = (toA.dx * direction.dy - toA.dy * direction.dx) / denom;
      if (t > 1e-6 && s >= 0 && s <= 1 && (best == 0 || t < best)) {
        best = t;
      }
    }
    return best;
  }

  static double _minDistance(Offset point, List<(Offset, Offset)> segments) {
    var best = double.infinity;
    for (final (a, b) in segments) {
      for (final sample in <Offset>[a, b]) {
        final d = (sample - point).distanceSquared;
        if (d < best) {
          best = d;
        }
      }
    }
    return best == double.infinity ? 0 : math.sqrt(best);
  }
}

/// Parses a stored SVG stroke path; shared by the canvas and tests so a
/// parsing regression shows up in geometry tests too.
Path parseStrokeSvg(String svgPath) {
  try {
    return parseSvgPathData(svgPath);
  } catch (error, stackTrace) {
    // 旧行为是静默返回空 Path，但那样笔画会无声消失；失败必须可见于日志。
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'stroke_reveal',
      context: ErrorDescription('解析 SVG 笔画路径失败'),
    ));
    return Path();
  }
}
