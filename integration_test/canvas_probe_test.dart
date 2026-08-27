import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bihua/features/detail/application/stroke_player_state.dart';
import 'package:bihua/features/detail/presentation/widgets/stroke_canvas.dart';
import 'package:bihua/features/dictionary/data/asset_dictionary_repository.dart';
import 'package:bihua/features/dictionary/domain/character_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// CanvasKit 像素探针：幽灵墨图层（saveLayer 低透明度合成）在真实 web
/// 引擎上的取证。宿主 Skia 金样已验证观感；这里防的是引擎分歧——
/// 2026-08-25 曾实证 Path.combine(union) 的几何结果在 CanvasKit 上
/// 吞掉字腔，因此任何绘制改动都要在真引擎上复测这三类断言：
///   1) 幽灵笔画以低透明度渲染（叠底色 ≈ 浅灰，非不透明墨、非消失）；
///   2) 幽灵笔画压在已写墨迹上还原成墨色（「突然加粗」病灶点）；
///   3) 完成态字腔保持镂空。
/// 探针图 900×900（300×300 画布 × pixelRatio 3），坐标取自
/// test/goldens/yang_canvas_*.png 的放大测量。
/// 字例数据走 AssetDictionaryRepository 分片链路——chars_3500.json
/// 已不在 pubspec 资产清单里，web 上 rootBundle 取不到（宿主测试
/// 用 dart:io 直读文件，不会暴露这一点）。
///
/// Run:
///   flutter drive -d chrome --headless \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/canvas_probe_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  /// 幽灵灰：叠底色后 ≈ #CFD0D3，明显亮于墨、暗于底色 F1F2F4。
  bool isGhostGrey(List<int> c) =>
      c[0] >= 180 && c[0] <= 236 && c[1] >= 180 && c[1] <= 236 &&
      c[2] >= 180 && c[2] <= 236;

  bool isInk(List<int> c) => c[0] <= 110 && c[1] <= 110 && c[2] <= 110;

  bool isBackground(List<int> c) =>
      c[0] >= 236 && c[1] >= 236 && c[2] >= 236;

  bool isRed(List<int> c) => c[0] >= 180 && c[1] <= 130 && c[2] <= 130;

  Future<ByteData> captureRgba(
    WidgetTester tester,
    StrokePlayerState state,
    CharacterEntry entry,
  ) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: RepaintBoundary(
                key: boundaryKey,
                child: StrokeCanvas(entry: entry, playerState: state),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // toImage 不包在 runAsync 里会永久挂起（宿主与 web 均如此）。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync<ByteData>(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!;
    });
    return bytes!;
  }

  List<int> px(ByteData data, int x, int y) {
    final o = (y * 900 + x) * 4;
    return [data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2)];
  }

  /// 「日」内部字腔区（远离外框笔画）：镂空 ⇔ 区内存在底色像素。
  /// 用区域扫描而非单点，避免手测坐标落在笔画上造成误报。
  bool holeAlive(ByteData data) {
    for (var y = 330; y <= 480; y += 2) {
      for (var x = 560; x <= 660; x += 2) {
        if (isBackground(px(data, x, y))) {
          return true;
        }
      }
    }
    return false;
  }

  String describe(ByteData data, int x, int y) =>
      '($x,$y)=${px(data, x, y)}';

  testWidgets('CanvasKit ghost-ink layer probes for 阳', (tester) async {
    final repository = AssetDictionaryRepository();
    final loaded = await repository.getByChar('阳');
    expect(loaded, isNotNull, reason: '分片链路未取到「阳」');
    final entry = loaded!;

    const total = 6; // 阳 = 横撇弯钩、竖、竖、横折、横、横

    // ── 1) 全灰 idle：幽灵层以低透明度渲染，字腔镂空 ──────────────────
    final idle = await captureRgba(
      tester,
      const StrokePlayerState(
        currentStrokeIndex: 0,
        isPlaying: false,
        speed: 1,
        progress: 0,
        totalStrokes: total,
      ),
      entry,
    );
    // 第 6 笔短横中段（叠在底色上的幽灵墨）。
    expect(
      isGhostGrey(px(idle, 669, 600)),
      isTrue,
      reason: 'idle 幽灵短横应为浅灰（saveLayer 透明度未生效或图层丢失): '
          '${describe(idle, 669, 600)}',
    );
    // 「日」内部字腔必须镂空（防 union 吞腔回归）。
    expect(
      holeAlive(idle),
      isTrue,
      reason: 'idle 字腔被填实（图层几何异常）',
    );

    // ── 2) 第 5 笔完成后：幽灵短横端帽压在黑竖笔上必须隐形（病灶点）──
    final after5 = await captureRgba(
      tester,
      const StrokePlayerState(
        currentStrokeIndex: 4,
        isPlaying: false,
        speed: 1,
        progress: 1,
        totalStrokes: total,
      ),
      entry,
    );
    // 左黑竖笔核心区 ∩ 灰短横端帽带：全部应为墨色。
    var inkCount = 0;
    var ghostOverInk = 0;
    final violations = <String>[];
    for (var y = 585; y <= 615; y += 1) {
      for (var x = 448; x <= 478; x += 1) {
        final c = px(after5, x, y);
        if (isInk(c)) {
          inkCount += 1;
        } else if (isGhostGrey(c)) {
          ghostOverInk += 1;
          if (violations.length < 5) {
            violations.add(describe(after5, x, y));
          }
        }
      }
    }
    final totalProbed = 31 * 31;
    expect(
      inkCount >= totalProbed * 0.98,
      isTrue,
      reason: '端帽压黑区墨色占比不足: $inkCount/$totalProbed',
    );
    expect(
      ghostOverInk,
      0,
      reason: '幽灵端帽在黑底上显形（「突然加粗」病灶仍在): $violations',
    );
    // 右端帽 ∩ 黑横折竖笔：还原成墨色本身（右侧病灶点）。
    expect(
      isInk(px(after5, 669, 600)),
      isTrue,
      reason: '右端帽压黑区应还原成墨色: ${describe(after5, 669, 600)}',
    );
    // 两竖笔之间的开放区幽灵短横仍可见。
    expect(
      isGhostGrey(px(after5, 570, 600)),
      isTrue,
      reason: '幽灵短横在空白处应可见: ${describe(after5, 570, 600)}',
    );
    // 状态渲染 sanity：第 5 笔（红短横）中段为红色。
    expect(
      isRed(px(after5, 560, 405)),
      isTrue,
      reason: '第 5 笔应为红色（状态未按预期渲染): ${describe(after5, 560, 405)}',
    );
    // 字腔仍镂空。
    expect(holeAlive(after5), isTrue, reason: 'after5 字腔被填实');

    // ── 3) 完成态：全墨且字腔镂空（防 union 吞腔回归）──────────────────
    final complete = await captureRgba(
      tester,
      const StrokePlayerState(
        currentStrokeIndex: total,
        isPlaying: false,
        speed: 1,
        progress: 1,
        totalStrokes: total,
      ),
      entry,
    );
    expect(
      isInk(px(complete, 669, 600)),
      isTrue,
      reason: '完成态短横应为墨色: ${describe(complete, 669, 600)}',
    );
    expect(
      holeAlive(complete),
      isTrue,
      reason: '完成态字腔被填实',
    );
  });
}
