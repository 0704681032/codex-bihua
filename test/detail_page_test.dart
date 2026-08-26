import 'dart:async';

import 'package:bihua/features/detail/application/reference_data.dart';
import 'package:bihua/features/detail/presentation/detail_page.dart';
import 'package:bihua/features/dictionary/application/dictionary_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_dictionary_repository.dart';
import 'helpers/reference_overrides.dart';

void main() {
  testWidgets('detail page play button toggles play state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository()),
          ...detailReferenceOverrides(<String>['笔']),
        ],
        child: const MaterialApp(
          home: DetailPage(char: '笔'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('暂停'), findsOneWidget);

    await tester.ensureVisible(find.text('暂停'));
    await tester.tap(find.text('暂停'), warnIfMissed: false);
    await tester.pump();

    expect(find.text('播放'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('detail page shows info sections and voice button is tappable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository()),
          ...detailReferenceOverrides(<String>['火']),
        ],
        child: const MaterialApp(
          home: DetailPage(char: '火'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('基本信息'), findsOneWidget);
    expect(find.text('笔顺表：共4笔'), findsOneWidget);
    expect(find.text('汉字解释'), findsOneWidget);
    expect(find.text('组词举例'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up_rounded).first);
    await tester.pump();

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
      'detail page hides fabricated info fields and 常速 chip matches autoplay',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository()),
          ...detailReferenceOverrides(<String>['火']),
        ],
        child: const MaterialApp(
          home: DetailPage(char: '火'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 结构/造字法/繁体/五行没有可靠数据源，已移除，不允许再出现。
    expect(find.text('结构'), findsNothing);
    expect(find.text('造字法'), findsNothing);
    expect(find.text('繁体'), findsNothing);
    expect(find.text('五行'), findsNothing);
    // 真实字段保留（label 渲染为「笔画数：」带全角冒号）。
    expect(find.text('笔画数：'), findsOneWidget);
    expect(find.text('部首：'), findsOneWidget);

    // 自动播放以常速（1.0）启动，对应档位必须高亮。
    final normalChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('常速'), matching: find.byType(ChoiceChip))
          .first,
    );
    expect(normalChip.selected, isTrue,
        reason: '自动播放速度应与「常速」预设一致');

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('stroke table tile tap jumps the player to that stroke',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository()),
          ...detailReferenceOverrides(<String>['笔']),
        ],
        child: const MaterialApp(
          home: DetailPage(char: '笔'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final provider = DetailPage.lastPlayerProvider;
    expect(provider, isNotNull);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(DetailPage)));

    // fake 字库没有 medianPoints，笔顺名会退化为「第N笔」，与瓦片标题
    // 文案重复，因此用 .first（标题在 name 之前，两者在同一个 InkWell 里）。
    await tester.ensureVisible(find.text('第2笔').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('第2笔').first, warnIfMissed: false);
    await tester.pump();

    final state = container.read(provider!);
    expect(state.currentStrokeIndex, 1, reason: '点击第 2 笔应跳到 index 1');
    expect(state.isPlaying, isFalse, reason: '跳转后应暂停');
    expect(state.progress, 1, reason: '跳转后该笔完整显示');

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('words/explanation show loading spinners while datasets pending',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository()),
          referenceForCharProvider('火')
              .overrideWith((ref) => Completer<CharReference>().future),
        ],
        child: const MaterialApp(
          home: DetailPage(char: '火'),
        ),
      ),
    );
    // 不能 pumpAndSettle：加载 spinner 是无限动画。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(2),
        reason: '组词与释义区应各自显示加载 spinner');
    // 未就绪时不得提前展示内置兜底词卡。
    expect(find.text('火山'), findsNothing);

    await tester.binding.setSurfaceSize(null);
  });
}
