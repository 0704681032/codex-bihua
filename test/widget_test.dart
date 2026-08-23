import 'package:bihua/app.dart';
import 'package:bihua/features/dictionary/application/dictionary_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_dictionary_repository.dart';

void main() {
  testWidgets('app boots into the home page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dictionaryRepositoryProvider
              .overrideWithValue(FakeDictionaryRepository()),
        ],
        child: const HanziStrokeApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('汉字举例'), findsOneWidget);
    expect(find.text('易错汉字'), findsOneWidget);
  });
}
