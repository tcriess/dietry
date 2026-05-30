import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/timezone.dart' as tz;
import 'tz_helper.dart';
import 'reminder_strings.dart';
import '../main_web_imports_web.dart'
    if (dart.library.io) '../main_web_imports.dart' as html;

/// Optional daily nudge to log food if nothing has been entered by the
/// afternoon (15:00). Opt-in and independent of the water reminder.
///
///   Android:          flutter_local_notifications — recurring 15:00, but
///                     pushed to tomorrow once an entry exists for today.
///   Web:              Browser Notification API (checked at fire time).
///   Desktop/Sonstige: In-App-Banner via [onInAppReminder].
///
/// Auf iOS: No-op (kein iOS-Notification-Support, wie WaterReminderService).
///
/// Notification text is hard-coded German to match WaterReminderService — the
/// service fires without a BuildContext, so it can't use AppLocalizations.
class FoodLogReminderService {
  FoodLogReminderService._();

  static const _enabledKey = 'food_log_reminder_enabled';
  static const _channelId = 'food_log_reminder';
  static const _channelName = 'Essens-Erinnerungen';
  static const _channelDesc =
      'Erinnerung, das Essen einzutragen, falls bis nachmittags nichts geloggt wurde';

  static const _id = 210;
  static const _reminderHour = 15;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _storage = const FlutterSecureStorage();

  static bool _initialized = false;
  static Timer? _timer;

  /// In-App-Banner callback (Desktop, solange App offen). Von DietryHome gesetzt.
  static void Function(String title, String body)? onInAppReminder;

  /// True wenn heute bereits mindestens ein Lebensmittel geloggt wurde.
  /// Von DietryHome gesetzt, damit der Service ohne DataStore-Zugriff prüfen kann.
  static bool Function()? getHasLoggedToday;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isSupported => !_isIOS;

  static Future<void> initialize() async {
    if (!isSupported) return;
    if (_isAndroid) {
      await ensureLocalTimezone();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {},
      );
    }
    _initialized = true;
    if (await isEnabled()) {
      _scheduleNextTimer();
      if (_isAndroid) await _scheduleSystemNotification();
    }
  }

  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    return await _storage.read(key: _enabledKey) == 'true';
  }

  static Future<bool> setEnabled(bool enabled) async {
    if (!isSupported) return false;
    if (enabled) {
      final granted = await _requestPermission();
      if (!granted) return false;
    }
    await _storage.write(key: _enabledKey, value: enabled.toString());
    if (enabled) {
      _scheduleNextTimer();
      if (_isAndroid) await _scheduleSystemNotification();
    } else {
      _stopTimer();
      if (_isAndroid) await _cancelSystemNotification();
    }
    return enabled;
  }

  /// Re-evaluate today's reminder. If an entry already exists for today (or it's
  /// already past 15:00), the next occurrence is pushed to tomorrow.
  static Future<void> refreshSchedule() async {
    if (!_initialized || !_isAndroid) return;
    if (!await isEnabled()) return;
    await _scheduleSystemNotification();
  }

  static Future<bool> _requestPermission() async {
    if (kIsWeb) {
      return await html.requestBrowserNotificationPermission();
    }
    if (_isAndroid) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await impl?.requestNotificationsPermission() ?? false;
    }
    return true;
  }

  static bool _hasLoggedToday() => getHasLoggedToday?.call() ?? false;

  // ── Timer (web/desktop, läuft solange App/Tab offen) ──────────────────────

  static DateTime _nextReminderTime() {
    final now = DateTime.now();
    final candidate = DateTime(now.year, now.month, now.day, _reminderHour);
    if (candidate.isAfter(now)) return candidate;
    return DateTime(now.year, now.month, now.day + 1, _reminderHour);
  }

  static void _scheduleNextTimer() {
    _timer?.cancel();
    final delay = _nextReminderTime().difference(DateTime.now());
    _timer = Timer(delay, () async {
      await _fireReminder();
      _scheduleNextTimer();
    });
  }

  static void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _fireReminder() async {
    if (_hasLoggedToday()) return; // already logged → no nudge
    if (kIsWeb) {
      html.showBrowserNotification(
          ReminderStrings.foodTitle, ReminderStrings.foodBody);
    } else if (!_isAndroid) {
      onInAppReminder?.call(ReminderStrings.foodTitle, ReminderStrings.foodBody);
    }
    // Android: handled by zonedSchedule.
  }

  // ── Android System-Notification ───────────────────────────────────────────

  static Future<void> _scheduleSystemNotification() async {
    if (!_initialized || !_isAndroid) return;
    await _cancelSystemNotification();

    final location = tz.local;
    final now = tz.TZDateTime.now(location);
    var scheduled =
        tz.TZDateTime(location, now.year, now.month, now.day, _reminderHour);

    // Skip today if it's already (nearly) past 15:00 or an entry already
    // exists; the daily recurrence (matchDateTimeComponents.time) continues.
    final isPast = scheduled.isBefore(now.add(const Duration(minutes: 1)));
    if (isPast || _hasLoggedToday()) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: _id,
      title: ReminderStrings.foodTitle,
      body: ReminderStrings.foodBody,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> _cancelSystemNotification() async {
    await _plugin.cancel(id: _id);
  }
}
