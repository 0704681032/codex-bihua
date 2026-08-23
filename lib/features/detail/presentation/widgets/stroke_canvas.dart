import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../dictionary/domain/character_entry.dart';
import '../../../dictionary/domain/stroke_path.dart';
import '../../application/stroke_player_state.dart';

class StrokeCanvas extends StatefulWidget {
  const StrokeCanvas({
    super.key,
    required this.entry,
    required this.playerState,
  });

  final CharacterEntry entry;
  final StrokePlayerState playerState;

  @override
  State<StrokeCanvas> createState() => _StrokeCanvasState();
}

class _StrokeCanvasState extends State<StrokeCanvas> {
  late List<Path> _paths;
  late List<List<double>> _widthProfiles;

  @override
  void initState() {
    super.initState();
    _paths = _parseStrokePaths(widget.entry);
    _widthProfiles = _computeWidthProfiles(widget.entry, _paths);
  }

  @override
  void didUpdateWidget(covariant StrokeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.char != widget.entry.char) {
      _paths = _parseStrokePaths(widget.entry);
      _widthProfiles = _computeWidthProfiles(widget.entry, _paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppPalette.guideRed, width: 3),
          color: const Color(0xFFF1F2F4),
        ),
        child: CustomPaint(
          painter: _StrokeCanvasPainter(
            paths: _paths,
            strokes: widget.entry.strokes,
            flipYAxis: widget.entry.flipYAxis,
            state: widget.playerState,
            widthProfiles: _widthProfiles,
          ),
        ),
      ),
    );
  }

  List<Path> _parseStrokePaths(CharacterEntry entry) {
    return entry.strokes.map((stroke) {
      try {
        return parseSvgPathData(stroke.svgPath);
      } catch (_) {
        return Path();
      }
    }).toList(growable: false);
  }

  /// Measures the local half-width of every stroke along its median so the
  /// reveal brush can follow the outline's true shape. Real glyph strokes
  /// taper (撇 thins towards the tip, 捺 widens), so a single brush radius
  /// cannot cover them — the red reveal would stop short of the grey
  /// outline.
  ///
  /// For each median sample the width is measured with two rays cast
  /// perpendicular to the writing direction: medians are not always
  /// centered inside the outline (捺 hugs its upper edge), so the distance
  /// to the nearest edge alone underestimates the far side. Overshooting
  /// is safe because the reveal is clipped by the outline anyway.
  List<List<double>> _computeWidthProfiles(
    CharacterEntry entry,
    List<Path> paths,
  ) {
    final profiles = <List<double>>[];
    for (var i = 0; i < entry.strokes.length; i += 1) {
      final medians = _medianPointsOf(entry.strokes[i]);
      if (medians == null || i >= paths.length) {
        profiles.add(const <double>[]);
        continue;
      }
      final segments = _outlineSegments(paths[i]);
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
          // Degenerate ray (open/synthetic path) — fall back to twice the
          // nearest-edge distance.
          width = 2 * _minDistance(medians[j], segments);
        }
        profile.add((width * 0.5 * 1.28 + 2).clamp(6.0, 110.0).toDouble());
      }
      profiles.add(profile);
    }
    return profiles;
  }

  List<Offset>? _medianPointsOf(StrokePath stroke) {
    final points = stroke.medianPoints
        .where((p) => p.length >= 2)
        .map((p) => Offset(p[0], p[1]))
        .toList(growable: false);
    if (points.length < 2) {
      return null;
    }
    return points;
  }

  /// Unit vector perpendicular to the median's writing direction at [index].
  Offset _localNormal(List<Offset> points, int index) {
    final a = points[math.max(0, index - 1)];
    final b = points[math.min(points.length - 1, index + 1)];
    final dir = b - a;
    final len = dir.distance;
    if (len == 0) {
      return const Offset(0, 1);
    }
    return Offset(-dir.dy / len, dir.dx / len);
  }

  /// Flattens the outline into segments, closing each contour so rays hit
  /// the start cap as well.
  List<(Offset, Offset)> _outlineSegments(Path path, {double step = 8}) {
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
  double _rayCast(
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

  double _minDistance(Offset point, List<(Offset, Offset)> segments) {
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

class _StrokeCanvasPainter extends CustomPainter {
  const _StrokeCanvasPainter({
    required this.paths,
    required this.strokes,
    required this.flipYAxis,
    required this.state,
    required this.widthProfiles,
  });

  static const double _viewBoxSize = 1024;

  final List<Path> paths;
  final List<StrokePath> strokes;
  final bool flipYAxis;
  final StrokePlayerState state;
  final List<List<double>> widthProfiles;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGuide(canvas, size);

    final sourceBounds = _computeSourceBounds(paths, flipYAxis);
    if (sourceBounds == null) {
      return;
    }

    const padding = 34.0;
    final maxWidth = size.width - padding * 2;
    final maxHeight = size.height - padding * 2;
    if (maxWidth <= 0 || maxHeight <= 0) {
      return;
    }

    final scaleX = maxWidth / sourceBounds.width;
    final scaleY = maxHeight / sourceBounds.height;
    final scale = math.min(scaleX, scaleY);

    final dx = (size.width - sourceBounds.width * scale) / 2 -
        sourceBounds.left * scale;
    final dy = (size.height - sourceBounds.height * scale) / 2 -
        sourceBounds.top * scale;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);
    if (flipYAxis) {
      canvas.translate(0, _viewBoxSize);
      canvas.scale(1, -1);
    }

    final maxSide = math.max(sourceBounds.width, sourceBounds.height);
    final lineStrokeWidth = (maxSide / 28).clamp(22, 42).toDouble();
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = lineStrokeWidth;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < paths.length; i += 1) {
      final path = paths[i];
      final done = state.completed || i < state.currentStrokeIndex;
      final color = done ? AppPalette.strokeBlack : AppPalette.strokeGrey;
      _paintStrokeShape(
        canvas: canvas,
        path: path,
        color: color,
        linePaint: linePaint,
        fillPaint: fillPaint,
      );
    }

    if (!state.completed &&
        state.currentStrokeIndex >= 0 &&
        state.currentStrokeIndex < paths.length) {
      final current = paths[state.currentStrokeIndex];
      final stroke = state.currentStrokeIndex < strokes.length
          ? strokes[state.currentStrokeIndex]
          : null;
      final progress = state.progress.clamp(0.0, 1.0).toDouble();

      if (progress >= 1) {
        final redFill = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.red;
        canvas.drawPath(current, redFill);
      } else {
        final medians = stroke == null ? null : _medianOffsets(stroke);
        final profile = state.currentStrokeIndex < widthProfiles.length
            ? widthProfiles[state.currentStrokeIndex]
            : const <double>[];
        if (medians != null) {
          // Real glyph data stores closed filled outlines, so a partial
          // extraction of the outline would reveal nothing meaningful.
          // Instead clip the full outline by the brush swept along the
          // stroke median: the brush radius follows the local stroke
          // width, so tapered strokes (撇/捺) are revealed exactly to
          // their edges.
          final sweep = _buildSweptCapsule(medians, profile, progress);
          canvas.save();
          canvas.clipPath(sweep);
          final redFill = Paint()
            ..style = PaintingStyle.fill
            ..color = Colors.red;
          canvas.drawPath(current, redFill);
          canvas.restore();
        } else {
          // Fallback for open/synthetic paths without median data.
          final redPaint = Paint()
            ..style =
                _isClosedPath(current) ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = lineStrokeWidth
            ..color = Colors.red;
          final partial = _extractPartialPath(current, progress);
          canvas.drawPath(partial, redPaint);
        }
      }
    }

    canvas.restore();
  }

  void _paintStrokeShape({
    required Canvas canvas,
    required Path path,
    required Color color,
    required Paint linePaint,
    required Paint fillPaint,
  }) {
    if (_isClosedPath(path)) {
      fillPaint.color = color;
      canvas.drawPath(path, fillPaint);
      return;
    }
    linePaint.color = color;
    canvas.drawPath(path, linePaint);
  }

  bool _isClosedPath(Path path) {
    for (final metric in path.computeMetrics()) {
      if (metric.isClosed) {
        return true;
      }
    }
    return false;
  }

  Rect? _computeSourceBounds(List<Path> paths, bool flipYAxis) {
    Rect? bounds;
    for (final path in paths) {
      var pathBounds = path.getBounds();
      if (flipYAxis && !pathBounds.isEmpty) {
        pathBounds = Rect.fromLTWH(
          pathBounds.left,
          _viewBoxSize - pathBounds.bottom,
          pathBounds.width,
          pathBounds.height,
        );
      }
      if (pathBounds.isEmpty) {
        continue;
      }
      bounds = bounds == null ? pathBounds : bounds.expandToInclude(pathBounds);
    }

    if (bounds == null) {
      return null;
    }

    final safeWidth = (bounds.width <= 0 ? 1 : bounds.width).toDouble();
    final safeHeight = (bounds.height <= 0 ? 1 : bounds.height).toDouble();
    return Rect.fromLTWH(bounds.left, bounds.top, safeWidth, safeHeight);
  }

  Path _extractPartialPath(Path source, double progress) {
    if (progress <= 0) {
      return Path();
    }
    if (progress >= 1) {
      return source;
    }

    final result = Path();
    for (final metric in source.computeMetrics()) {
      final segment = metric.extractPath(0, metric.length * progress);
      result.addPath(segment, Offset.zero);
    }
    return result;
  }

  List<Offset>? _medianOffsets(StrokePath stroke) {
    return _medianOffsetsFromPoints(stroke.medianPoints);
  }

  List<Offset>? _medianOffsetsFromPoints(List<List<double>> points) {
    if (points.length < 2) {
      return null;
    }
    final offsets = points
        .where((p) => p.length >= 2)
        .map((p) => Offset(p[0], p[1]))
        .toList(growable: false);
    if (offsets.length < 2 || _polylineLength(offsets) <= 0) {
      return null;
    }
    return offsets;
  }

  /// Builds the region covered by a round brush travelling along the
  /// median polyline for the first [progress] fraction of its length.
  /// [widthProfile] carries a per-sample radius so the brush follows the
  /// stroke's true (tapering) width. Used as a clip mask so the real
  /// stroke outline is revealed exactly where the pen has passed.
  Path _buildSweptCapsule(
    List<Offset> rawPoints,
    List<double> widthProfile,
    double progress,
  ) {
    // Grow the profile to match the smoothed polyline before sweeping.
    final pairs = _smoothWithWidth(rawPoints, widthProfile);
    final points = pairs.$1;
    final radii = pairs.$2;

    final sweep = Path();
    void stamp(Offset center, double radius) {
      sweep.addOval(Rect.fromCircle(center: center, radius: radius));
    }

    if (points.isEmpty) {
      return sweep;
    }

    final totalLength = _polylineLength(points);
    if (totalLength <= 0) {
      stamp(points.first, radii.first);
      return sweep;
    }

    final target = totalLength * progress.clamp(0.0, 1.0);

    stamp(points.first, radii.first);
    var travelled = 0.0;

    for (var i = 0; i < points.length - 1; i += 1) {
      final start = points[i];
      final end = points[i + 1];
      final radius = math.max(radii[i], radii[i + 1]);
      final segLength = (end - start).distance;
      if (segLength <= 0) {
        continue;
      }
      // Stamp densely enough that consecutive circles always overlap and
      // the swept edge reads as one smooth stroke instead of beads.
      final step = math.max(radius * 0.3, 0.8);

      if (travelled + segLength < target - step) {
        // Whole segment is well inside the reveal; stamp sparsely.
        final direction = (end - start) / segLength;
        var offset = step;
        while (offset < segLength) {
          final t = offset / segLength;
          stamp(start + direction * offset,
              _lerp(radii[i], radii[i + 1], t));
          offset += step * 2;
        }
        travelled += segLength;
        continue;
      }

      final direction = (end - start) / segLength;

      var offset = 0.0;
      while (offset < segLength) {
        final remaining = target - travelled;
        if (remaining <= 0) {
          return sweep;
        }
        final advance =
            math.min(math.min(step, segLength - offset), remaining);
        offset += advance;
        travelled += advance;
        stamp(start + direction * offset,
            _lerp(radii[i], radii[i + 1], offset / segLength));
        if (travelled >= target) {
          return sweep;
        }
      }
    }

    return sweep;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Chaikin-style corner cutting applied to (point, radius) pairs: rounds
  /// the sharp joints of the median polyline so the animated pen path
  /// bends naturally, while interpolating the brush width along the way.
  (List<Offset>, List<double>) _smoothWithWidth(
    List<Offset> input,
    List<double> profile,
  ) {
    if (input.length < 3) {
      final radii = List<double>.generate(
        input.length,
        (i) => i < profile.length ? profile[i] : 24,
        growable: false,
      );
      return (input, radii);
    }
    final points = <Offset>[input.first];
    final radii = <double>[profile.isEmpty ? 24 : profile.first];

    double radiusAt(int index) =>
        index >= 0 && index < profile.length ? profile[index] : 24;

    for (var i = 0; i < input.length - 1; i += 1) {
      final a = input[i];
      final b = input[i + 1];
      final ra = radiusAt(i);
      final rb = radiusAt(i + 1);
      points.add(a + (b - a) * 0.25);
      radii.add(ra + (rb - ra) * 0.25);
      points.add(a + (b - a) * 0.75);
      radii.add(ra + (rb - ra) * 0.75);
    }
    points.add(input.last);
    radii.add(profile.isEmpty ? 24 : profile.last);
    return (points, radii);
  }

  double _polylineLength(List<Offset> points) {
    var sum = 0.0;
    for (var i = 0; i < points.length - 1; i += 1) {
      sum += (points[i + 1] - points[i]).distance;
    }
    return sum;
  }

  void _drawGuide(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = AppPalette.guideRed.withValues(alpha: 0.8)
      ..strokeWidth = 3;

    final midX = size.width / 2;
    final midY = size.height / 2;

    _drawDashedLine(
        canvas, Offset(midX, 0), Offset(midX, size.height), guidePaint);
    _drawDashedLine(
        canvas, Offset(0, midY), Offset(size.width, midY), guidePaint);
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 11.0;
    const gap = 8.0;
    final delta = to - from;
    final distance = delta.distance;
    if (distance == 0) {
      return;
    }
    final direction = delta / distance;

    var offset = 0.0;
    while (offset < distance) {
      final start = from + direction * offset;
      final end = from + direction * (offset + dash).clamp(0, distance);
      canvas.drawLine(start, end, paint);
      offset += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _StrokeCanvasPainter oldDelegate) {
    return oldDelegate.paths != paths || oldDelegate.state != state;
  }
}
