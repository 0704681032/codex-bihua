import 'dart:convert';
import 'dart:io';

import 'package:bihua/features/detail/application/stroke_player_state.dart';
import 'package:bihua/features/detail/presentation/widgets/stroke_canvas.dart';
import 'package:bihua/features/dictionary/domain/character_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders StrokeCanvas at the exact player states produced by
/// 上一笔/下一笔 so drawing regressions can be inspected visually.
///
/// Regenerate the PNGs into test/goldens/ with:
///   flutter test --update-goldens test/manual_canvas_states_test.dart
void main() {
  final rawData = File('assets/data/chars_3500.json').readAsStringSync();
  final data = jsonDecode(rawData) as List<dynamic>;
  final entry = CharacterEntry.fromJson(
    Map<String, dynamic>.from(
      data.firstWhere((e) => (e as Map)['char'] == '字')
          as Map<dynamic, dynamic>,
    ),
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
      matchesGoldenFile('goldens/canvas_$name.png'),
    );
  }

  testWidgets('render prev/next states for visual inspection',
      (tester) async {
    const total = 6; // 字 = 6 strokes

    await renderState(
      tester,
      'playing_stroke2_mid',
      const StrokePlayerState(
        currentStrokeIndex: 1,
        isPlaying: true,
        speed: 1.6,
        progress: 0.5,
        totalStrokes: total,
      ),
    );

    await renderState(
      tester,
      'after_next',
      const StrokePlayerState(
        currentStrokeIndex: 2,
        isPlaying: false,
        speed: 1.6,
        progress: 0.01,
        totalStrokes: total,
      ),
    );

    await renderState(
      tester,
      'after_prev',
      const StrokePlayerState(
        currentStrokeIndex: 3,
        isPlaying: false,
        speed: 1.6,
        progress: 1,
        totalStrokes: total,
      ),
    );
  });
}
