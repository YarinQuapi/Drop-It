import 'package:drop_it/api.dart';
import 'package:drop_it/copy.dart';
import 'package:drop_it/main.dart';
import 'package:drop_it/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApi extends Api {
  final calls = <(String, Object?)>[];

  @override
  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Object? body,
  }) async {
    calls.add(('$method $path', body));
    return {};
  }
}

Future<void> pump(WidgetTester tester, FakeApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppleTheme(Brightness.light),
      home: OneTimeMealScreen(api: api, t: const Copy('en'), meal: 'dinner'),
    ),
  );
}

void main() {
  testWidgets('logs the typed values without creating a food', (tester) async {
    final api = FakeApi();
    await pump(tester, api);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), ' Wedding dinner ');
    await tester.enterText(fields.at(1), '650,5');
    await tester.enterText(fields.at(2), '30');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(api.calls, hasLength(1));
    expect(api.calls.single.$1, 'POST /api/days/today/one-time-entries');
    expect(api.calls.single.$2, {
      'meal': 'dinner',
      'name': 'Wedding dinner',
      'calories': 650.5,
      'protein': 30,
      'carbohydrates': 0,
      'fat': 0,
      'fiber': 0,
      'sugars': 0,
      'sodium': 0,
    });
  });

  testWidgets('needs a name and calories', (tester) async {
    final api = FakeApi();
    await pump(tester, api);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(api.calls, isEmpty);
    expect(find.byType(ErrorText), findsOneWidget);
  });
}
