import 'package:bihua/core/router/app_router.dart';
import 'package:bihua/features/dictionary/application/dictionary_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fake_dictionary_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('query and open detail page', (tester) async {
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

    await tester.enterText(find.byType(TextField).first, '笔');
    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('「笔」的笔顺详情'), findsOneWidget);

    await tester.tap(find.text('播放'));
    await tester.pump();

    expect(find.text('暂停'), findsOneWidget);
  });
}
