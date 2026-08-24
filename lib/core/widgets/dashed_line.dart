import 'dart:ui' show Canvas;

import 'package:flutter/material.dart' show Offset, Paint;

/// 画一条从 [from] 到 [to] 的虚线。
///
/// 各调用方保留自己的 dash/gap 节奏（画布十字引导 11/8、首页 logo
/// 十字 7/6、字卡田字格 4/3），这里只共享绘制循环。
void drawDashedLine(
  Canvas canvas,
  Offset from,
  Offset to,
  Paint paint, {
  double dash = 11,
  double gap = 8,
}) {
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
