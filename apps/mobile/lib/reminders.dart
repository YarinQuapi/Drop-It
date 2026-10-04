import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Reminders {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  Future<void> schedule({
    required bool enabled,
    required int startHour,
    required int endHour,
    required String startText,
    required String endText,
    required String doneText,
    String? endsAtIso,
  }) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    if (!enabled) return;
    await _daily(1, startHour, startText);
    await _daily(2, endHour, endText);
    if (endsAtIso != null) {
      final when = DateTime.parse(endsAtIso).toLocal();
      final zoned = tz.TZDateTime.from(when, tz.local);
      if (zoned.isAfter(tz.TZDateTime.now(tz.local))) {
        await _plugin.zonedSchedule(
          id: 3,
          title: 'Drop It',
          body: doneText,
          scheduledDate: zoned,
          notificationDetails: const NotificationDetails(iOS: DarwinNotificationDetails()),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  Future<void> _daily(int id, int hour, String body) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: id,
      title: 'Drop It',
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(iOS: DarwinNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
