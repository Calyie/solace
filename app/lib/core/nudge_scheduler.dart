// Gentle reminders on the device (PLAN 13: few, timed, generic on the lock screen; TASKLIST B3): today's planned steps
// and the chosen check-in and weekly session times, scheduled by the system's own notifications. Nothing is sent
// anywhere. Everything is rescheduled when the app opens and whenever it saves, so a change of plan, time or clock is
// picked up; the reminders are absolute instants (the device's time zone name is not needed).
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';
import 'today_plan.dart';

class NudgeScheduler {
  NudgeScheduler([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false, _asked = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('reminders', 'Reminders',
        channelDescription: 'Planned steps and your session times', importance: Importance.defaultImportance),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const darwin = DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false,
        requestSoundPermission: false);
    await _plugin.initialize(settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: darwin, macOS: darwin,
        linux: LinuxInitializationSettings(defaultActionName: 'Open')));
    _ready = true;
  }

  Future<void> _askPermission() async {
    if (_asked) return;
    _asked = true;
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
    await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
  }

  /// Replaces whatever was scheduled with the reminders from [now]; none when the person turned them off. A platform
  /// that cannot schedule (Linux) is skipped quietly: reminders are a help, never a reason to fail.
  Future<void> reschedule(AppData d, DateTime now) async {
    try {
      await _init();
      await _plugin.cancelAll();
      // nothing before the first-run steps are done (helper C, P-3: the system's notification prompt covered the
      // Welcome screen at the very first start); the prompt itself comes at most once a run (_askPermission)
      final nudges = d.settings.remindersOn && d.settings.onboarded ? nudgesFor(d, now) : const <Nudge>[];
      if (nudges.isEmpty) return;
      await _askPermission();
      for (final (i, n) in nudges.indexed) {
        await _plugin.zonedSchedule(id: i, scheduledDate: tz.TZDateTime.from(n.at, tz.UTC), title: n.title, body: n.body,
            notificationDetails: _details, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: switch (n.repeat) {
              Repeat.daily => DateTimeComponents.time,
              Repeat.weekly => DateTimeComponents.dayOfWeekAndTime,
              Repeat.none => null,
            });
      }
    } catch (e) {
      debugPrint('reminders not scheduled: ${e.runtimeType}');
    }
  }
}
