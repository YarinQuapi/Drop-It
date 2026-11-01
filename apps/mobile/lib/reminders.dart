import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ReminderCopy {
  const ReminderCopy({
    required this.start,
    required this.lead30,
    required this.lead60,
    required this.late,
    required this.done,
  });

  final String start;
  final String lead30;
  final String lead60;
  final String late;
  final String done;
}

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
    required List<Map<String, dynamic>> notifications,
    required ReminderCopy copy,
  }) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    var id = 1;
    for (final item in notifications) {
      final atIso = item['at'] as String?;
      final kind = item['kind'] as String?;
      if (atIso == null || kind == null) continue;
      final when = DateTime.parse(atIso).toLocal();
      final zoned = tz.TZDateTime.from(when, tz.local);
      if (!zoned.isAfter(now)) continue;
      final body = _bodyFor(kind, item['leadMinutes'], copy);
      if (body == null) continue;
      await _plugin.zonedSchedule(
        id: id++,
        title: 'Drop It',
        body: body,
        scheduledDate: zoned,
        notificationDetails: const NotificationDetails(iOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  String? _bodyFor(String kind, Object? leadMinutes, ReminderCopy copy) {
    switch (kind) {
      case 'lead':
        final minutes = leadMinutes is int
            ? leadMinutes
            : int.tryParse('$leadMinutes') ?? 0;
        if (minutes >= 60) return copy.lead60;
        if (minutes >= 30) return copy.lead30;
        return copy.start;
      case 'late':
        return copy.late;
      case 'done':
        return copy.done;
      default:
        return null;
    }
  }
}
