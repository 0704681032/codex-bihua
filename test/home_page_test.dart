import 'package:bihua/core/router/app_router.dart';
import 'package:bihua/features/dictionary/application/dictionary_providers.dart';
import 'package:bihua/features/dictionary/domain/character_entry.dart';
import 'package:bihua/features/dictionary/domain/stroke_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_dictionary_repository.dart';
import 'helpers/reference_overrides.dart';

void main() {
  testWidgets('home page renders and can navigate to detail by search',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider.overrideWithValue(FakeDictionaryRepository()),
          ...detailReferenceOverrides(<String>['笔']),
        ],
        child: const MaterialApp(
          initialRoute: AppRouter.home,
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('汉字举例'), findsOneWidget);
    expect(find.text('易错汉字'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '笔');
    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('笔的笔顺详情'), findsOneWidget);
  });

  testWidgets(
      'pinyin filter sheet: dismissing keeps the filter, 清除筛选 clears it',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider.overrideWithValue(FakeDictionaryRepository()),
        ],
        child: const MaterialApp(
          initialRoute: AppRouter.home,
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 选择拼音 bi3 → 筛选生效，结果面板出现。
    await tester.tap(find.text('拼音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bi3').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('筛选结果'), findsOneWidget);

    // 再次打开弹层后点遮罩关闭 → 筛选必须保留（下滑/点遮罩 ≠ 清除）。
    await tester.tap(find.text('拼音'));
    await tester.pumpAndSettle();
    expect(find.text('按拼音筛选'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('按拼音筛选'), findsNothing);
    expect(find.textContaining('筛选结果'), findsOneWidget);

    // 显式点「清除筛选」才会清空。
    await tester.tap(find.text('拼音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.textContaining('筛选结果'), findsNothing);
  });

  testWidgets('home shows retry button when dictionary warm-up fails',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository()),
          dictionaryWarmUpProvider.overrideWith((ref) async {
            throw Exception('boom');
          }),
        ],
        child: const MaterialApp(
          initialRoute: AppRouter.home,
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('字库加载失败，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter results show total count and 展开全部', (tester) async {
    // 造 100 个同笔画数的字，验证「共 N 字」计数与分批展示。
    final seed = <CharacterEntry>[
      for (var i = 0; i < 100; i++)
        CharacterEntry(
          char: String.fromCharCode(0x4E00 + i),
          pinyin: 'bi3',
          radical: '竹',
          strokeCount: 3,
          strokes: List<StrokePath>.generate(
            3,
            (j) => StrokePath(
              order: j + 1,
              svgPath: 'M100 ${120 + j * 40} L860 ${120 + j * 40}',
            ),
          ),
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository(seed: seed)),
        ],
        child: const MaterialApp(
          initialRoute: AppRouter.home,
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('笔画'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3画'));
    await tester.pumpAndSettle();

    expect(find.text('筛选结果（共 100 字）'), findsOneWidget);
    expect(find.text('已显示前 80 字，点击显示全部'), findsOneWidget);

    await tester.ensureVisible(find.text('已显示前 80 字，点击显示全部'));
    await tester.tap(find.text('已显示前 80 字，点击显示全部'));
    await tester.pumpAndSettle();

    expect(find.text('已显示前 80 字，点击显示全部'), findsNothing,
        reason: '展开全部后按钮应消失');
    expect(find.text('筛选结果（共 100 字）'), findsOneWidget);
  });
}
