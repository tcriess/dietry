import 'dart:convert';

/// A saved quick-add for the activity Quick Add sheet.
///
/// Captures everything needed to instant-log a [PhysicalActivity] without
/// reopening the full add form. Stored in SharedPreferences as JSON, so
/// shortcuts are device-local and never sync across devices.
class ActivityShortcut {
  final String id;
  final String label;

  /// Enum name (e.g. `'running'`). Resolved back to [ActivityType] at
  /// log-time via `ActivityType.values.firstWhere`.
  final String activityType;

  /// Optional reference to an `activity_database` row — non-null only
  /// when the shortcut was built from a DB-backed activity.
  final String? activityId;

  final int durationMinutes;

  /// Hint stored at shortcut-creation time. Re-used directly when
  /// re-logging so the value matches what the user saw when they
  /// pinned the shortcut, even if their weight has since changed.
  final double? caloriesBurned;

  final double? distanceKm;
  final String? notes;

  const ActivityShortcut({
    required this.id,
    required this.label,
    required this.activityType,
    this.activityId,
    required this.durationMinutes,
    this.caloriesBurned,
    this.distanceKm,
    this.notes,
  });

  factory ActivityShortcut.fromJson(Map<String, dynamic> json) =>
      ActivityShortcut(
        id: json['id'] as String,
        label: json['label'] as String,
        activityType: json['activity_type'] as String,
        activityId: json['activity_id'] as String?,
        durationMinutes: json['duration_minutes'] as int,
        caloriesBurned: json['calories_burned'] != null
            ? (json['calories_burned'] as num).toDouble()
            : null,
        distanceKm: json['distance_km'] != null
            ? (json['distance_km'] as num).toDouble()
            : null,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'activity_type': activityType,
        if (activityId != null) 'activity_id': activityId,
        'duration_minutes': durationMinutes,
        if (caloriesBurned != null) 'calories_burned': caloriesBurned,
        if (distanceKm != null) 'distance_km': distanceKm,
        if (notes != null) 'notes': notes,
      };

  static ActivityShortcut fromJsonString(String s) =>
      ActivityShortcut.fromJson(jsonDecode(s) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());
}
