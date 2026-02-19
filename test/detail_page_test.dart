import 'package:bihua/features/detail/presentation/detail_page.dart';
import 'package:bihua/features/dictionary/application/dictionary_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_dictionary_repository.dart';

void main() {
  testWidgets('detail page play button toggles play state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider.overrideWithValue(FakeDictionaryRepository()),
        ],
        child: const MaterialApp(
          home: DetailPage(char: '笔'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('播放'), findsOneWidget);

    await tester.tap(find.text('播放'));
    await tester.pump();

    expect(find.text('暂停'), findsOneWidget);
  });
}
