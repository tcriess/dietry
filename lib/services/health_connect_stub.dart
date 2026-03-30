// Stub für Web / Desktop — health package nicht verfügbar
import '../models/physical_activity.dart';
import '../models/user_body_data.dart';

Future<bool> requestHealthPermissions() async => false;

Future<List<PhysicalActivity>> fetchHealthActivities({
  required DateTime start,
  required DateTime end,
}) async => [];

Future<List<UserBodyMeasurement>> fetchHealthBodyMeasurements({
  required DateTime start,
  required DateTime end,
}) async => [];
