import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../main_web_imports_web.dart'
    if (dart.library.io) '../main_web_imports.dart' as html;

/// Verwaltet Wasser-Erinnerungen auf allen Plattformen.
///
/// Ein Toggle steuert alles – je nach Plattform unterschiedlich:
///   Android:        flutter_local_notifications (System-Notifications)
///   Web:            Browser Notification API
///   Desktop/Sonstige: In-App-Banner (onInAppReminder-Callback)
///
/// Erinnerungszeiten: 12:00, 16:00, 20:00 Uhr.
/// Auf iOS: No-op.
class WaterReminderService {
  WaterReminderService._();

  static const _enabledKey = 'water_reminder_enabled';
  static const _channelId = 'water_reminder';
  static const _channelName = 'Wasser-Erinnerungen';
  static const _channelDesc =
      'Erinnerungen zum regelmäßigen Trinken von Wasser';

  static const _ids = [201, 202, 203];
  static const _reminderHours = [12, 16, 20];

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _storage = const FlutterSecureStorage();

  static bool _initialized = false;
  static Timer? _timer;

  /// Callback für In-App-Banner (Desktop, solange App offen).
  /// Wird von DietryHome registriert.
  static void Function(String title, String body)? onInAppReminder;

  /// Liefert (aktuellerIntake, waterGoal) für den heutigen Tag.
  /// Wird von DietryHome gesetzt, damit der Service prüfen kann ob eine
  /// Benachrichtigung sinnvoll ist, ohne direkt auf den DataStore zuzugreifen.
  static (int intake, int goal) Function()? getWaterStatus;

  // Fenster für die Hochrechnung: erstes bis letztes Reminder-Fenster
  static const _windowStartHour = 12;
  static const _windowEndHour = 20;

  // ── Plattform-Erkennung ───────────────────────────────────────────────────

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// True wenn diese Plattform Notifications unterstützt.
  static bool get isSupported => !_isIOS;

  // ── Initialisierung ────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (!isSupported) return;

    if (_isAndroid) {
      tz_data.initializeTimeZones();
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
      if (_isAndroid) await _scheduleSystemNotifications();
    }
  }

  // ── Öffentliche API ────────────────────────────────────────────────────────

  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    return await _storage.read(key: _enabledKey) == 'true';
  }

  /// Aktiviert oder deaktiviert Erinnerungen.
  /// Gibt true zurück wenn erfolgreich aktiviert (Berechtigung erteilt).
  static Future<bool> setEnabled(bool enabled) async {
    if (!isSupported) return false;

    if (enabled) {
      final granted = await _requestPermission();
      if (!granted) return false;
    }

    await _storage.write(key: _enabledKey, value: enabled.toString());

    if (enabled) {
      _scheduleNextTimer();
      if (_isAndroid) await _scheduleSystemNotifications();
    } else {
      _stopTimer();
      if (_isAndroid) await _cancelSystemNotifications();
    }
    return enabled;
  }

  // ── Berechtigungen ────────────────────────────────────────────────────────

  static Future<bool> _requestPermission() async {
    if (kIsWeb) {
      return await html.requestBrowserNotificationPermission();
    }
    if (_isAndroid) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await impl?.requestNotificationsPermission() ?? false;
    }
    // Desktop: kein Permission-Dialog nötig
    return true;
  }

  // ── Timer (läuft solange App/Tab offen) ───────────────────────────────────

  /// Berechnet den nächsten Erinnerungszeitpunkt aus [_reminderHours].
  static DateTime _nextReminderTime() {
    final now = DateTime.now();
    for (final hour in _reminderHours) {
      final candidate = DateTime(now.year, now.month, now.day, hour);
      if (candidate.isAfter(now)) return candidate;
    }
    // Alle heutigen Zeiten sind vorbei → erster Slot morgen
    return DateTime(now.year, now.month, now.day + 1, _reminderHours.first);
  }

  /// Startet einen einmaligen Timer bis zum nächsten Erinnerungszeitpunkt.
  /// Nach dem Auslösen wird automatisch der übernächste geplant.
  static void _scheduleNextTimer() {
    _timer?.cancel();
    final delay = _nextReminderTime().difference(DateTime.now());
    _timer = Timer(delay, () async {
      await _fireReminder();
      _scheduleNextTimer(); // nächsten Slot planen
    });
  }

  static void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Benachrichtigungs-Logik ───────────────────────────────────────────────

  /// Prüft ob eine Benachrichtigung sinnvoll ist.
  ///
  /// Gibt false zurück wenn:
  /// - Tagesziel bereits erreicht
  /// - Vor dem ersten Erinnerungsfenster (vor 12 Uhr)
  /// - Hochgerechneter Tagesendwert ≥ 50 % des Ziels
  static bool _shouldNotify() {
    final status = getWaterStatus?.call();
    if (status == null) return true; // kein Datenzugang → lieber zu viel

    final (intake, goal) = status;
    if (goal <= 0) return false;
    if (intake >= goal) return false; // Ziel erreicht

    final now = DateTime.now();
    final windowStart =
        DateTime(now.year, now.month, now.day, _windowStartHour);
    final windowEnd = DateTime(now.year, now.month, now.day, _windowEndHour);
    final totalMinutes = windowEnd.difference(windowStart).inMinutes; // 480
    final elapsedMinutes = now.difference(windowStart).inMinutes;

    if (elapsedMinutes <= 0) return false; // noch vor 12 Uhr

    final elapsed = elapsedMinutes.clamp(0, totalMinutes) / totalMinutes;
    final projected = intake / elapsed;

    // Nur benachrichtigen wenn Hochrechnung < 50 % des Ziels
    return projected < goal / 2;
  }

  static Future<void> _fireReminder() async {
    if (!_shouldNotify()) return;

    const title = '💧 Zeit zum Trinken!';
    const body = 'Denk daran, regelmäßig zu trinken.';

    if (kIsWeb) {
      // Web: Browser-Notification
      html.showBrowserNotification(title, body);
    } else if (!_isAndroid) {
      // Desktop/Sonstige: In-App-Banner
      onInAppReminder?.call(title, body);
    }
    // Android: System-Notifications sind bereits via zonedSchedule geplant
  }

  // ── Android System-Notifications ──────────────────────────────────────────

  static Future<void> _scheduleSystemNotifications() async {
    if (!_initialized || !_isAndroid) return;
    await _cancelSystemNotifications();

    final location = tz.local;
    final now = tz.TZDateTime.now(location);

    for (int i = 0; i < _ids.length; i++) {
      var scheduled = tz.TZDateTime(
          location, now.year, now.month, now.day, _reminderHours[i]);
      if (scheduled.isBefore(now.add(const Duration(minutes: 1)))) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        id: _ids[i],
        title: '💧 Zeit zum Trinken!',
        body: 'Denk daran, regelmäßig zu trinken.',
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
  }

  static Future<void> _cancelSystemNotifications() async {
    for (final id in _ids) {
      await _plugin.cancel(id: id);
    }
  }
}
