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

  @override
  void initState() {
    super.initState();
    _paths = _parseStrokePaths(widget.entry);
  }

  @override
  void didUpdateWidget(covariant StrokeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.char != widget.entry.char) {
      _paths = _parseStrokePaths(widget.entry);
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
}

class _StrokeCanvasPainter extends CustomPainter {
  const _StrokeCanvasPainter({
    required this.paths,
    required this.strokes,
    required this.flipYAxis,
    required this.state,
  });

  static const double _viewBoxSize = 1024;

  final List<Path> paths;
  final List<StrokePath> strokes;
  final bool flipYAxis;
  final StrokePlayerState state;

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

      if (_isClosedPath(current)) {
        // Outline glyph data should render as filled stroke blocks.
        final redFill = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.red;
        canvas.drawPath(current, redFill);
      } else if (stroke != null && stroke.medianPoints.length >= 2) {
        final medianPath = _extractMedianPath(stroke.medianPoints, progress);
        if (medianPath != null) {
          final redLinePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = _estimateMedianStrokeWidth(current, lineStrokeWidth)
            ..color = Colors.red;
          canvas.drawPath(medianPath, redLinePaint);
        }
      } else {
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

  Path? _extractMedianPath(List<List<double>> points, double progress) {
    if (points.length < 2 || progress <= 0) {
      return null;
    }

    final offsets = points
        .where((p) => p.length >= 2)
        .map((p) => Offset(p[0], p[1]))
        .toList(growable: false);
    if (offsets.length < 2) {
      return null;
    }

    final totalLength = _polylineLength(offsets);
    if (totalLength <= 0) {
      return null;
    }

    final target = totalLength * progress.clamp(0, 1);
    final result = Path()..moveTo(offsets.first.dx, offsets.first.dy);

    var drawn = 0.0;
    for (var i = 0; i < offsets.length - 1; i += 1) {
      final start = offsets[i];
      final end = offsets[i + 1];
      final segLength = (end - start).distance;
      if (segLength <= 0) {
        continue;
      }

      if (drawn + segLength <= target) {
        result.lineTo(end.dx, end.dy);
        drawn += segLength;
        continue;
      }

      final remain = (target - drawn).clamp(0, segLength);
      final ratio = remain / segLength;
      final mid = Offset(
        start.dx + (end.dx - start.dx) * ratio,
        start.dy + (end.dy - start.dy) * ratio,
      );
      result.lineTo(mid.dx, mid.dy);
      break;
    }

    return result;
  }

  double _polylineLength(List<Offset> points) {
    var sum = 0.0;
    for (var i = 0; i < points.length - 1; i += 1) {
      sum += (points[i + 1] - points[i]).distance;
    }
    return sum;
  }

  double _estimateMedianStrokeWidth(Path shape, double fallback) {
    final bounds = shape.getBounds();
    if (bounds.isEmpty) {
      return fallback;
    }
    final estimated =
        (math.min(bounds.width, bounds.height) * 0.42).clamp(16, 52);
    return estimated.toDouble();
  }

  void _drawGuide(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = AppPalette.guideRed.withOpacity(0.8)
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
