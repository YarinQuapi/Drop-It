import 'package:drop_it/api.dart';
import 'package:drop_it/copy.dart';
import 'package:drop_it/main.dart';
import 'package:drop_it/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

/// Serves a fixed weight overview and records goal changes.
class FakeApi extends Api {
  FakeApi(this.overview);
  Map<String, dynamic> overview;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Object? body,
  }) async {
    calls.add('$method $path${body == null ? '' : ' $body'}');
    return overview;
  }
}

Map<String, dynamic> onTrack() {
  final now = DateTime.now().toUtc();
  String at(int days) => now.add(Duration(days: days)).toIso8601String();
  return {
    'weights': [
      for (final (i, kg) in [74.2, 73.5, 72.8, 72.0, 71.0].indexed)
        {
          'id': 'w$i',
          'weightKg': kg,
          'loggedAt': at(-(4 - i) * 7),
          'source': i.isEven ? 'manual' : 'health',
        },
    ],
    'goal': {'targetKg': 68, 'startKg': 74.2, 'setAt': at(-28)},
    'trend': <String, dynamic>{
      'status': 'on_track',
      'currentKg': 71,
      'remainingKg': 3,
      'progress': 0.52,
      'ratePerWeekKg': -0.8,
      'etaAt': at(26),
      'etaDay': at(26).substring(0, 10),
      'line': {'fromAt': at(-28), 'fromKg': 74.3, 'perDayKg': -0.114},
    },
  };
}

Future<void> pumpWeight(WidgetTester tester, FakeApi api, String lang) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppleTheme(Brightness.light),
      home: Directionality(
        textDirection: lang == 'he' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: WeightScreen(api: api, t: Copy(lang)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('time until the goal reads naturally in both languages', () {
    const en = Copy('en');
    const he = Copy('he');
    expect(en.until(0), 'Today');
    expect(en.until(1), 'In 1 day');
    expect(en.until(13), 'In 13 days');
    expect(en.until(49), 'In 7 weeks');
    expect(en.until(120), 'In 4 months');
    expect(en.until(800), 'In 2 years');
    expect(he.until(1), 'בעוד יום');
    expect(he.until(14), 'בעוד שבועיים');
    expect(he.until(49), 'בעוד 7 שבועות');
    expect(he.until(365), 'בעוד 12 חודשים');
  });

  testWidgets('shows the estimated goal date and pace when on track', (
    tester,
  ) async {
    await pumpWeight(tester, FakeApi(onTrack()), 'en');
    expect(find.text('Estimated goal date'), findsOneWidget);
    expect(find.text('In 4 weeks at your current pace'), findsOneWidget);
    expect(find.text('−0.8'), findsOneWidget);
    expect(find.text('Goal 68 kg'), findsOneWidget);
    expect(find.text('Trend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders right to left in Hebrew', (tester) async {
    await pumpWeight(tester, FakeApi(onTrack()), 'he');
    expect(find.text('תאריך יעד משוער'), findsOneWidget);
    expect(find.text('בעוד 4 שבועות בקצב הנוכחי'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers to set a goal, then saves it', (tester) async {
    final api = FakeApi({...onTrack(), 'goal': null, 'trend': null});
    await pumpWeight(tester, api, 'en');
    expect(find.text('Estimated goal date'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '68');
    api.overview = onTrack();
    await tester.tap(find.text('Set goal'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('PUT /api/weights/goal {targetKg: 68}'));
    expect(find.text('Estimated goal date'), findsOneWidget);
  });

  testWidgets('explains a missing estimate and lets the goal be removed', (
    tester,
  ) async {
    final data = onTrack();
    (data['trend'] as Map<String, dynamic>)
      ..['status'] = 'off_track'
      ..['etaAt'] = null
      ..['ratePerWeekKg'] = 0.3;
    final api = FakeApi(data);
    await pumpWeight(tester, api, 'en');
    expect(find.text('No estimated date'), findsOneWidget);
    expect(find.text('+0.3'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove goal'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('DELETE /api/weights/goal'));
  });
}
