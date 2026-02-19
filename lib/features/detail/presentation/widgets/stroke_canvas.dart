import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../dictionary/domain/character_entry.dart';
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
    required this.state,
  });

  final List<Path> paths;
  final StrokePlayerState state;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGuide(canvas, size);

    const viewBox = 1024.0;
    final scale = (size.shortestSide - 24) / viewBox;
    final dx = (size.width - viewBox * scale) / 2;
    final dy = (size.height - viewBox * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 74;

    for (var i = 0; i < paths.length; i += 1) {
      final path = paths[i];
      if (state.completed || i < state.currentStrokeIndex) {
        strokePaint.color = AppPalette.strokeBlack;
        canvas.drawPath(path, strokePaint);
      } else {
        strokePaint.color = AppPalette.strokeGrey;
        canvas.drawPath(path, strokePaint);
      }
    }

    if (!state.completed &&
        state.currentStrokeIndex >= 0 &&
        state.currentStrokeIndex < paths.length) {
      strokePaint.color = Colors.red;
      final current = paths[state.currentStrokeIndex];
      final partial = _extractPartialPath(current, state.progress.clamp(0, 1));
      canvas.drawPath(partial, strokePaint);
    }

    canvas.restore();
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

  void _drawGuide(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = AppPalette.guideRed.withOpacity(0.8)
      ..strokeWidth = 3;

    final midX = size.width / 2;
    final midY = size.height / 2;

    _drawDashedLine(canvas, Offset(midX, 0), Offset(midX, size.height), guidePaint);
    _drawDashedLine(canvas, Offset(0, midY), Offset(size.width, midY), guidePaint);
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
