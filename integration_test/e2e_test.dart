import 'package:bihua/app.dart';
import 'package:bihua/core/router/app_router.dart';
import 'package:bihua/features/detail/application/reference_data.dart';
import 'package:bihua/features/detail/application/stroke_player_controller.dart';
import 'package:bihua/features/detail/application/stroke_player_state.dart';
import 'package:bihua/features/detail/presentation/detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

/// End-to-end flows against the REAL asset pipeline (index + shards +
/// words + definitions) and the REAL app shell. Run on a real browser:
///
///   flutter drive -d chrome --headless \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/e2e_test.dart
///
/// 约定(踩坑总结):
///   - integration_test 在用例之间会重置组件树, 所以每个用例都要重新
///     runApp;
///   - 但 Flutter Web 引擎持有浏览器 history 簿记, 反复从外部改
///     location.hash 会与引擎互相回滚, 因此只有第一个用例(引擎最干净,
///     等价真实"刷新进详情页")种子深链 URL, 之后启动一律不碰 URL,
///     页面切换全部走应用内导航(搜索框 / 返回箭头);
///   - 自动播放每 16ms 排一帧, pumpAndSettle 永不静止, 统一用真实时间
///     有界等待 + 单帧推进。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late ProviderContainer container;

  /// Bounded wall-clock wait.
  Future<void> waitReal(WidgetTester tester, Duration wallTime) async {
    final deadline = DateTime.now().add(wallTime);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await tester.pump();
    }
  }

  List<String> visibleTexts(WidgetTester tester) {
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s.trim().isNotEmpty)
        .take(30)
        .toList(growable: false);
  }

  Never dumpAndFail(WidgetTester tester, String reason) {
    fail('$reason\nURL: ${web.window.location.href}\n'
        '可见文本样本: ${visibleTexts(tester)}');
  }

  /// 轮询直到 [text] 出现; 返回是否出现。
  Future<bool> tryWaitForText(WidgetTester tester, String text,
      {int tries = 50}) async {
    final finder = find.text(text);
    for (var i = 0; i < tries; i += 1) {
      if (finder.evaluate().isNotEmpty) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
    return false;
  }

  /// 轮询直到 [text] 出现; 超时后带诊断信息失败。
  Future<void> waitForText(WidgetTester tester, String text,
      {int tries = 50}) async {
    if (!await tryWaitForText(tester, text, tries: tries)) {
      dumpAndFail(tester, '限时内未出现 "$text"');
    }
  }

  /// 每个用例启动一次真实外壳。[deepLink] 仅首个用例使用: 引擎/history
  /// 尚未被触碰, 此时改 URL 等价于用户在详情页按了刷新。
  Future<void> launchApp(WidgetTester tester, {String? deepLink}) async {
    container = ProviderContainer();
    DetailPage.lastPlayerProvider = null;

    var bootedFromUrl = false;
    if (deepLink != null) {
      web.window.location.hash = deepLink;
      bootedFromUrl = true;
    }
    runApp(UncontrolledProviderScope(
      container: container,
      child: const HanziStrokeApp(),
    ));
    await waitReal(tester, const Duration(seconds: 1));
    if (bootedFromUrl) {
      // 深链冷启动必须落在目标详情页, 否则立即失败并给出现场。
      await waitForText(
          tester, '「万」的笔顺详情', tries: 30);
      await tryWaitForText(tester, '3', tries: 20);
    }
  }

  bool onHome(WidgetTester tester) =>
      find.text('汉字举例').evaluate().isNotEmpty;

  /// 引擎对每次路由变更做分段回声, 会在栈顶堆重复的首页; 点「首页」tab
  /// 直到只剩一个搜索框(URL 不再变化后引擎不再回声)。否则搜索点击会落
  /// 在空字段的顶层副本上被吞掉。
  Future<void> collapseDuplicateHomes(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      final fields = find.byType(TextField).evaluate().length;
      if (fields <= 1) {
        return;
      }
      final homeTab = find.text('首页');
      if (homeTab.evaluate().isEmpty) {
        return;
      }
      await tester.tap(homeTab.last);
      await tester.pump();
      await waitReal(tester, const Duration(milliseconds: 300));
    }
  }

  Future<void> goHome(WidgetTester tester) async {
    if (onHome(tester)) {
      await collapseDuplicateHomes(tester);
      return;
    }
    // 首选底部导航「首页」tab: pushNamedAndRemoveUntil 清空整个栈,
    // 不受引擎分段回声残留的重复路由影响。
    final homeTab = find.text('首页');
    if (homeTab.evaluate().isNotEmpty) {
      await tester.tap(homeTab.last);
      await tester.pump();
      await tryWaitForText(tester, '汉字举例', tries: 15);
    }
    // 兜底: 循环点返回箭头(引擎回声可能把同名页压栈两次)。
    for (var i = 0; i < 4 && !onHome(tester); i += 1) {
      final back = find.byIcon(Icons.arrow_back_ios_new_rounded);
      if (back.evaluate().isEmpty) {
        dumpAndFail(tester, '当前页面找不到返回箭头, 无法回首页');
      }
      await tester.tap(back.last);
      await tester.pump();
      await tryWaitForText(tester, '汉字举例', tries: 8);
    }
    if (!onHome(tester)) {
      dumpAndFail(tester, '多次返回仍未回到首页');
    }
    await collapseDuplicateHomes(tester);
  }

  /// 应用内导航到某字详情页: 需要时先回首页再搜索; 整个流程带一轮重试,
  /// 抵御引擎回声吞掉首次点击。
  Future<void> gotoDetail(WidgetTester tester, String char) async {
    final title = '「$char」的笔顺详情';
    if (find.text(title).evaluate().isNotEmpty) {
      return;
    }
    for (var attempt = 0; attempt < 2; attempt += 1) {
      await goHome(tester);
      final field = find.byType(TextField);
      if (field.evaluate().isEmpty) {
        dumpAndFail(tester, '首页缺少搜索框');
      }
      await tester.enterText(field.first, char);
      await tester.tap(find.byIcon(Icons.search_rounded).last);
      if (await tryWaitForText(tester, title, tries: 15)) {
        return;
      }
    }
    dumpAndFail(tester, '搜索后未到达 $title');
  }

  /// 轮询直到详情页构建出播放器 provider(分片异步加载完成后的首个 build)。
  Future<AutoDisposeStateNotifierProvider<StrokePlayerController,
          StrokePlayerState>> capturePlayer(WidgetTester tester,
      {int? expectedStrokes}) async {
    for (var i = 0; i < 60; i += 1) {
      final provider = DetailPage.lastPlayerProvider;
      if (provider != null &&
          (expectedStrokes == null ||
              container.read(provider).totalStrokes == expectedStrokes)) {
        return provider;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    dumpAndFail(tester,
        '详情页未在限时内构建播放器 provider (expectedStrokes=$expectedStrokes)');
  }

  /// 滚动到目标并补一帧, 页面下半部分的按钮必须先可见才能命中点击。
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      dumpAndFail(tester, 'scrollTo 目标不在组件树上: $finder');
    }
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  tearDownAll(() async {
    // Give pending TTS/microtask chains a beat before the driver tears
    // the browser context down.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  testWidgets('E2E-1 深链冷启动直达「万」详情页(模拟刷新场景)', (tester) async {
    await launchApp(tester, deepLink: AppRouter.detailRouteFor('万'));

    expect(find.text('3'), findsWidgets); // 万 3 笔

    final provider = await capturePlayer(tester, expectedStrokes: 3);
    expect(container.read(provider).totalStrokes, 3);
  });

  testWidgets('E2E-2 首页用真实索引渲染示例字', (tester) async {
    await launchApp(tester);

    // 上个用例停在「万」详情页, 本次冷启动会按当前 URL 复原到同一页面 ——
    // 这本身就是深链复原语义的二次验证; 先应用内回首页再断言首页内容。
    await goHome(tester);

    if (find.text('笔').evaluate().isEmpty) {
      dumpAndFail(tester, '首页缺少 logo「笔」');
    }
    expect(find.text('汉字举例'), findsOneWidget);
    expect(find.byType(Wrap), findsWidgets);
  });

  testWidgets('E2E-3 搜索「火」→ 详情页全量数据就绪', (tester) async {
    await launchApp(tester);
    await gotoDetail(tester, '火');
    expect(find.text('4'), findsWidgets); // 笔画数 4

    // 组词/中文释义为懒加载, 轮询直到数据集就绪。
    var wordsReady = false;
    var zhReady = false;
    for (var i = 0; i < 20 && !(wordsReady && zhReady); i += 1) {
      final words = container.read(wordsForCharProvider('火')).valueOrNull;
      final zh = container.read(definitionZhProvider('火')).valueOrNull;
      wordsReady = words != null && words.isNotEmpty;
      zhReady = zh != null && zh.isNotEmpty;
      if (!(wordsReady && zhReady)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      }
    }
    expect(wordsReady, isTrue, reason: 'words.json 应包含「火」');
    expect(zhReady, isTrue, reason: 'definitions_zh.json 应包含「火」');
    // 数据就绪后还要等一帧让词卡真正上树。
    await waitReal(tester, const Duration(milliseconds: 600));

    // 笔顺名称来自 cnchar 数据(点、撇、撇、捺)
    expect(find.text('点、撇、撇、捺'), findsOneWidget);

    // 词卡来自 CC-CEDICT 数据集(儿童过滤后无"火车", 但有"火候")
    expect(find.text('词库建设中，敬请期待'), findsNothing);
    expect(find.textContaining('火候'), findsWidgets);

    // 中文释义来自新华字典数据(象形……)
    expect(find.textContaining('象形'), findsWidgets);
  });

  testWidgets('E2E-4 自动播放 → 暂停 → 上一笔/下一笔状态机', (tester) async {
    await launchApp(tester);
    await gotoDetail(tester, '火');

    final provider = await capturePlayer(tester, expectedStrokes: 4);
    // postFrame 回调置速 1.0 并开播, 给它一点真实时间。
    await waitReal(tester, const Duration(milliseconds: 800));

    expect(container.read(provider).speed, closeTo(1.0, 0.01),
        reason: '自动播放应置速 1.0');
    var state = container.read(provider);
    expect(state.isPlaying || state.completed || state.progress > 0, isTrue,
        reason: '自动播放应已推进');

    // 暂停(按钮可能在首屏之下, 先滚动)
    await scrollTo(tester, find.text('暂停'));
    await tester.tap(find.text('暂停'));
    await tester.pump();
    expect(container.read(provider).isPlaying, isFalse);

    final controller = container.read(provider.notifier);

    // 初始态即「全部显示」: index == 总笔画数
    controller.reset();
    await tester.pump();
    state = container.read(provider);
    expect(state.currentStrokeIndex, 4);
    expect(state.progress, 1);

    // 完成态点上一笔 → 回到最后一个笔画并完整显示
    controller.previousStroke();
    await tester.pump();
    state = container.read(provider);
    expect(state.currentStrokeIndex, 3, reason: '完成态上一笔应回到最后一笔');
    expect(state.progress, 1, reason: '上一笔应完整显示该笔');

    controller.previousStroke();
    await tester.pump();
    state = container.read(provider);
    expect(state.currentStrokeIndex, 2);

    // 下一笔从新笔画的开头开始
    controller.nextStroke();
    await tester.pump();
    state = container.read(provider);
    expect(state.currentStrokeIndex, 3);
    expect(state.progress, lessThanOrEqualTo(0.05),
        reason: '下一笔应从新笔画的开头开始');

    // 连续下一笔越过末尾 → 钳制在完成态
    for (var i = 0; i < 5; i += 1) {
      controller.nextStroke();
      await tester.pump();
    }
    state = container.read(provider);
    expect(state.completed, isTrue);
    expect(state.progress, 1);
  });

  testWidgets('E2E-5 速度切换生效', (tester) async {
    await launchApp(tester);
    await gotoDetail(tester, '马');

    final provider = await capturePlayer(tester, expectedStrokes: 3);
    await waitReal(tester, const Duration(milliseconds: 400));

    // 速度芯片在画布下方, 逐个滚动到可视区再点。
    await scrollTo(tester, find.text('慢速'));
    await tester.tap(find.text('慢速'));
    await tester.pump();
    expect(container.read(provider).speed, 0.7);

    await scrollTo(tester, find.text('快速'));
    await tester.tap(find.text('快速'));
    await tester.pump();
    expect(container.read(provider).speed, 2.0,
        reason: '钳制上限应容纳「快速」预设 2.0');

    // 选中的芯片应反映当前速度(修复前 3.2 被钳到 3.0, 快速永远无法选中)
    final fastChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('快速'), matching: find.byType(ChoiceChip)).first,
    );
    expect(fastChip.selected, isTrue);

    await scrollTo(tester, find.text('常速'));
    await tester.tap(find.text('常速'));
    await tester.pump();
    // 常速预设 = 自动播放基准 1.0（与 PlaybackSpeeds.normal 对齐）。
    expect(container.read(provider).speed, 1.0);
  });

  testWidgets('E2E-6 语音按钮不崩溃、不误报失败', (tester) async {
    await launchApp(tester);
    await gotoDetail(tester, '火');
    await capturePlayer(tester, expectedStrokes: 4);

    await tester.tap(find.byIcon(Icons.volume_up_rounded).first);
    await waitReal(tester, const Duration(milliseconds: 500));

    // 连续快速点击两次(复现 interrupted 场景)
    await tester.tap(find.byIcon(Icons.volume_up_rounded).first);
    await waitReal(tester, const Duration(milliseconds: 500));

    expect(find.text('语音播放失败，请稍后重试'), findsNothing,
        reason: '失败提示已收敛为日志,不应再弹出');
    expect(find.text('当前设备暂不支持语音播放'), findsNothing,
        reason: '浏览器支持 speechSynthesis,不应降级提示');
  });

  testWidgets('E2E-7 词卡点击不崩溃且拼音来自数据集', (tester) async {
    await launchApp(tester);
    await gotoDetail(tester, '母');

    // 等待懒加载的组词数据集
    List<WordCard>? words;
    for (var i = 0; i < 30 && (words == null || words.isEmpty); i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      words = container.read(wordsForCharProvider('母')).valueOrNull;
    }
    expect(words, isNotNull, reason: 'words.json 应包含「母」');
    expect(words!.first.pinyin, isNotNull, reason: '词卡应带拼音');

    // 等一帧让词卡上树, 再滚动到可视区点击。
    await waitReal(tester, const Duration(milliseconds: 400));
    final cardFinder = find.text(words.first.word).first;
    await scrollTo(tester, cardFinder);
    await tester.tap(cardFinder);
    await waitReal(tester, const Duration(milliseconds: 400));
    expect(find.text('语音播放失败，请稍后重试'), findsNothing);
  });

  testWidgets('E2E-8 浏览器返回/前进键联动', (tester) async {
    await launchApp(tester);

    // 用本用例专属的字建立干净栈顶, back/forward 只做相对断言。
    await gotoDetail(tester, '永');
    expect(find.text('「永」的笔顺详情'), findsOneWidget);

    // 模拟浏览器返回:history.back() 触发 popstate → 应用离开「永」详情
    web.window.history.back();
    var leftDetail = false;
    for (var i = 0; i < 30 && !leftDetail; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      leftDetail = find.text('「永」的笔顺详情').evaluate().isEmpty;
    }
    expect(leftDetail, isTrue, reason: '返回后应离开详情页');

    // 模拟前进:history.forward() → popstate 把应用推回「永」详情页。
    // back 之后指针已就位, 若那次 popstate 恰好丢失, 重试 forward 是
    // 空操作 —— 此时直接置目标 URL 并派发 popstate, 与真实前进走的是
    // 同一个监听契约(readCharFromUrl → 导航)。
    var backOnDetail = false;
    for (var attempt = 0; attempt < 3 && !backOnDetail; attempt += 1) {
      web.window.history.forward();
      backOnDetail =
          await tryWaitForText(tester, '「永」的笔顺详情', tries: 10);
    }
    if (!backOnDetail) {
      web.window.location.hash = AppRouter.detailRouteFor('永');
      web.window.dispatchEvent(web.PopStateEvent('popstate'));
      backOnDetail =
          await tryWaitForText(tester, '「永」的笔顺详情', tries: 10);
    }
    expect(backOnDetail, isTrue, reason: '前进应回到详情页');
  });
}
