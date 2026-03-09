import 'package:bihua/features/detail/presentation/detail_page.dart';
import 'package:bihua/features/dictionary/application/dictionary_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_dictionary_repository.dart';

void main() {
  testWidgets('detail page play button toggles play state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository()),
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
}
