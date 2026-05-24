import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/physical_activity.dart';
import '../models/user_body_data.dart';
import '../platform_utils.dart';

// Conditional import: health package only available on mobile
import 'health_connect_stub.dart'
    if (dart.library.io) 'health_connect_native.dart';

/// Abstrahiert den Zugriff auf Health Connect (Android) und HealthKit (iOS).
///
/// Auf Web und Desktop wird nichts importiert (Stub).
/// Die eigentliche Implementierung liegt in [health_connect_native.dart].
class HealthConnectService {
  /// Prüfe ob Health Connect / HealthKit auf diesem Gerät verfügbar ist.
  static bool get isSupported =>
      !kIsWeb && (isAndroid() || isIOS());

  /// Prüfe Verfügbarkeit und fordere Berechtigungen an.
  ///
  /// Gibt `true` zurück wenn alle benötigten Berechtigungen gewährt wurden.
  Future<bool> requestPermissions() => requestHealthPermissions();

  /// Check whether HC permissions are *already* granted, without prompting.
  ///
  /// Use this on the silent refresh path. The `health` package's
  /// `requestAuthorization()` is known to return `false` on subsequent calls
  /// after the OS already granted permissions (it doesn't re-prompt) — so
  /// silent paths must check rather than re-request.
  Future<bool> hasPermissions() => hasHealthPermissions();

  /// Importiere Aktivitäten aus Health Connect / HealthKit.
  ///
  /// Gibt eine Liste von [PhysicalActivity] zurück, die noch nicht in der DB
  /// sind. Die Caller-Seite speichert sie via [PhysicalActivityService].
  Future<List<PhysicalActivity>> importActivities({
    required DateTime start,
    required DateTime end,
  }) => fetchHealthActivities(start: start, end: end);

  /// Importiere Körpermessungen (Gewicht, Körperfett).
  ///
  /// Gibt eine Liste von [UserBodyMeasurement] zurück, direkt speicherbar
  /// via [UserBodyMeasurementsService.saveMeasurement].
  Future<List<UserBodyMeasurement>> importBodyMeasurements({
    required DateTime start,
    required DateTime end,
  }) => fetchHealthBodyMeasurements(start: start, end: end);
}
