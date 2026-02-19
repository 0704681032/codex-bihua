import 'package:bihua/core/router/app_router.dart';
import 'package:bihua/features/dictionary/application/dictionary_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_dictionary_repository.dart';

void main() {
  testWidgets('home page renders and can navigate to detail by search',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider.overrideWithValue(FakeDictionaryRepository()),
        ],
        child: MaterialApp(
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

    expect(find.text('「笔」的笔顺详情'), findsOneWidget);
  });
}
