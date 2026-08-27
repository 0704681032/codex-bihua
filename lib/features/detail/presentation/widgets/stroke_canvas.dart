import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dashed_line.dart' as dashed;
import '../../../dictionary/domain/character_entry.dart';
import '../../../dictionary/domain/stroke_path.dart';
import '../../application/stroke_geometry.dart';
import '../../application/stroke_player_state.dart';
import '../../application/stroke_reveal.dart';

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
  late StrokeGeometry _geometry;

  @override
  void initState() {
    super.initState();
    _geometry = StrokeGeometryCache.of(widget.entry);
  }

  @override
  void didUpdateWidget(covariant StrokeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 按内容校验键取缓存：同字不同笔画数据不会复用旧几何，命中则零开销。
    final geometry = StrokeGeometryCache.of(widget.entry);
    if (!identical(geometry, _geometry)) {
      _geometry = geometry;
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
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _StrokeCanvasPainter(
              paths: _geometry.paths,
              strokes: widget.entry.strokes,
              flipYAxis: widget.entry.flipYAxis,
              state: widget.playerState,
              brushStamps: _geometry.brushStamps,
            ),
          ),
        ),
      ),
    );
  }
}

class _StrokeCanvasPainter extends CustomPainter {
  const _StrokeCanvasPainter({
    required this.paths,
    required this.strokes,
    required this.flipYAxis,
    required this.state,
    required this.brushStamps,
  });

  static const double _viewBoxSize = 1024;

  final List<Path> paths;
  final List<StrokePath> strokes;
  final bool flipYAxis;
  final StrokePlayerState state;
  final List<List<BrushStamp>> brushStamps;

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
      if (!(state.completed || i < state.currentStrokeIndex)) {
        continue;
      }
      _paintStrokeShape(
        canvas: canvas,
        path: paths[i],
        color: AppPalette.strokeBlack,
        linePaint: linePaint,
        fillPaint: fillPaint,
      );
    }

    // 待写笔画画进一层「幽灵墨」：层内用不透明墨色保证重叠处颜色均匀，
    // 整层低透明度合成后叠在黑笔上还原成墨色本身——圆头端帽不再从黑底
    // 里显形（读作笔画「突然加粗」）。勿改回不透明浅灰；勿用 Path.combine
    // 合并多笔轮廓（web CanvasKit 的 union 会吞字腔），取证记录见
    // AGENTS.md 2026-08-25 待办。
    final hasGhost =
        !state.completed && state.currentStrokeIndex < paths.length;
    if (hasGhost) {
      canvas.saveLayer(null, Paint()..color = AppPalette.strokeGhost);
      for (var i = 0; i < paths.length; i += 1) {
        if (state.completed || i < state.currentStrokeIndex) {
          continue;
        }
        _paintStrokeShape(
          canvas: canvas,
          path: paths[i],
          color: AppPalette.strokeBlack,
          linePaint: linePaint,
          fillPaint: fillPaint,
        );
      }
      canvas.restore();
    }

    if (!state.completed &&
        state.currentStrokeIndex >= 0 &&
        state.currentStrokeIndex < paths.length) {
      final current = paths[state.currentStrokeIndex];
      final progress = state.progress.clamp(0.0, 1.0).toDouble();

      if (progress >= 1) {
        final redFill = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.red;
        canvas.drawPath(current, redFill);
      } else if (state.currentStrokeIndex < brushStamps.length &&
          brushStamps[state.currentStrokeIndex].isNotEmpty) {
        // Clip the real outline by the swept reveal brush: the red is
        // bounded by the glyph itself while following the pen exactly.
        final sweep =
            StrokeReveal.sweptCapsule(brushStamps[state.currentStrokeIndex], progress);
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

  void _drawGuide(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = AppPalette.guideRed.withValues(alpha: 0.8)
      ..strokeWidth = 3;

    final midX = size.width / 2;
    final midY = size.height / 2;

    dashed.drawDashedLine(
        canvas, Offset(midX, 0), Offset(midX, size.height), guidePaint);
    dashed.drawDashedLine(
        canvas, Offset(0, midY), Offset(size.width, midY), guidePaint);
  }

  @override
  bool shouldRepaint(covariant _StrokeCanvasPainter oldDelegate) {
    return oldDelegate.paths != paths || oldDelegate.state != state;
  }
}
