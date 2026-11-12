import 'package:home_widget/home_widget.dart';

import 'copy.dart';

/// Pushes today's calories and the fasting state to the iOS home screen widget
/// through the shared App Group, then asks WidgetKit to reload the timeline.
class WidgetSync {
  static const String appGroupId = 'group.dev.yarinlevi.dropit';
  static const String iosWidgetName = 'DropItWidget';

  bool _ready = false;

  Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      _ready = true;
    } catch (_) {}
  }

  Future<void> update({
    required Copy t,
    required bool signedIn,
    Map<String, dynamic>? fasting,
    Map<String, dynamic>? day,
  }) async {
    if (!_ready) return;
    try {
      final totals = (day?['totals'] as Map?)?.cast<String, dynamic>();
      final values = <String, Object?>{
        'signedIn': signedIn,
        'rtl': t.he,
        'consumed': ((totals?['calories'] as num?) ?? 0).round(),
        'goal': ((day?['goalKcal'] as num?) ?? 0).round(),
        'fastEnabled': fasting?['enabled'] == true,
        'fastRunning': fasting?['running'] == true,
        'fastEndsAt': fasting?['endsAt'] as String? ?? '',
        'fastStartHour': (fasting?['startHour'] as num?)?.toInt() ?? -1,
        'fastEndHour': (fasting?['endHour'] as num?)?.toInt() ?? -1,
        'fastLengthHours': (fasting?['lengthHours'] as num?)?.toInt() ?? 0,
        'lblCalories': t.widgetCalories,
        'lblKcalLeft': t.widgetKcalLeft,
        'lblKcalOver': t.widgetKcalOver,
        'lblFastTitle': t.widgetFastTitle,
        'lblFastLeft': t.widgetFastLeft,
        'lblFastDone': t.widgetFastDone,
        'lblFastOff': t.widgetFastOff,
        'lblFastWindow': t.widgetFastWindow,
        'lblSignedOut': t.widgetSignedOut,
      };
      for (final entry in values.entries) {
        await HomeWidget.saveWidgetData(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(iOSName: iosWidgetName);
    } catch (_) {}
  }
}
