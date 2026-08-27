import 'dart:convert';
import 'dart:io';

import 'package:bihua/features/detail/application/stroke_player_state.dart';
import 'package:bihua/features/detail/presentation/widgets/stroke_canvas.dart';
import 'package:bihua/features/dictionary/domain/character_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「阳」状态截图矩阵(Futter 测试渲染侧)。
///
/// 灰/黑笔交接观感问题的取证基线:覆盖 未播放 / 每笔完成 /
/// 交接瞬间(第4-6笔书写中)/ 播放完成 全部环节。真引擎(CanvasKit)
/// 对照截图见 截图/阳-状态矩阵/,生成方式是手动在 Chrome 里逐步暂停。
///
/// Regenerate the PNGs with:
///   flutter test --update-goldens test/yang_canvas_states_test.dart
void main() {
  final rawData = File('assets/data/chars_3500.json').readAsStringSync();
  final data = jsonDecode(rawData) as List<dynamic>;
  final parsed = CharacterEntry.fromJson(
    Map<String, dynamic>.from(
      data.firstWhere((e) => (e as Map)['char'] == '阳')
          as Map<dynamic, dynamic>,
    ),
  );
  // 与仓储 _entryFromJson 相同的规范化:按 order 排序 + 中线数据
  // 存在时翻转 Y 轴(Make Me a Hanzi 是 y-up 坐标系)。
  final ordered = parsed.strokes.toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  final entry = parsed.copyWith(
    strokes: ordered,
    flipYAxis: ordered.any((s) => s.medianPoints.isNotEmpty),
  );

  Future<void> renderState(
    WidgetTester tester,
    String name,
    StrokePlayerState state,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: ValueKey(name),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 300,
                child: StrokeCanvas(entry: entry, playerState: state),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(ValueKey(name)),
      matchesGoldenFile('goldens/yang_canvas_$name.png'),
    );
  }

  testWidgets('render full playback stage matrix for 阳', (tester) async {
    const total = 6; // 阳 = 横撇弯钩、竖、竖、横折、横、横

    // 未播放:全灰。
    await renderState(
      tester,
      '01_idle',
      const StrokePlayerState(
        currentStrokeIndex: 0,
        isPlaying: false,
        speed: 1,
        progress: 0,
        totalStrokes: total,
      ),
    );

    // 第一笔书写中。
    await renderState(
      tester,
      '02_playing_stroke1_mid',
      const StrokePlayerState(
        currentStrokeIndex: 0,
        isPlaying: true,
        speed: 0.6,
        progress: 0.5,
        totalStrokes: total,
      ),
    );

    // 逐笔完成态(jumpToStroke:该笔红色,之前黑,之后灰)。
    for (var k = 1; k <= total; k += 1) {
      await renderState(
        tester,
        'after_stroke$k',
        StrokePlayerState(
          currentStrokeIndex: k - 1,
          isPlaying: false,
          speed: 1,
          progress: 1,
          totalStrokes: total,
        ),
      );
    }

    // 交接瞬间:日部 横折(第4笔)与两条短横(第5/6笔)书写中——
    // 灰笔贴黑笔引发「突然加粗」观感的环节。
    await renderState(
      tester,
      '11_playing_stroke4_mid',
      const StrokePlayerState(
        currentStrokeIndex: 3,
        isPlaying: true,
        speed: 0.6,
        progress: 0.5,
        totalStrokes: total,
      ),
    );
    await renderState(
      tester,
      '12_playing_stroke5_mid',
      const StrokePlayerState(
        currentStrokeIndex: 4,
        isPlaying: true,
        speed: 0.6,
        progress: 0.45,
        totalStrokes: total,
      ),
    );
    await renderState(
      tester,
      '13_playing_stroke6_mid',
      const StrokePlayerState(
        currentStrokeIndex: 5,
        isPlaying: true,
        speed: 0.6,
        progress: 0.5,
        totalStrokes: total,
      ),
    );

    // 播放完成:全黑。
    await renderState(
      tester,
      '14_complete',
      const StrokePlayerState(
        currentStrokeIndex: total,
        isPlaying: false,
        speed: 1,
        progress: 1,
        totalStrokes: total,
      ),
    );
  });
}
