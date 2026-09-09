import '../models/user_body_data.dart';
import 'neon_database_service.dart';
import 'package:dio/dio.dart';
import 'app_logger.dart';

/// Service für statische Profildaten (in users Tabelle)
class UserProfileService {
  final NeonDatabaseService _db;
  
  UserProfileService(this._db);
  
  String? get _userId => _db.userId;
  
  /// Hole aktuelles Profil
  Future<UserProfile?> getCurrentProfile() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return null;
      }
      
      final userId = _userId;
      if (userId == null) return null;
      
      final response = await _db.client
          .from('users')
          .select('id, birthdate, height, gender, activity_level, weight_goal, '
              'exercise_credit_factor')
          .eq('id', userId)
          .maybeSingle();
      
      if (response == null) return null;
      
      return UserProfile.fromJson(response);
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden des Profils: $e');
      return null;
    }
  }
  
  /// Aktualisiere Profil
  Future<void> updateProfile(UserProfile profile) async {
    try {
      appLogger.i('💾 Aktualisiere Profil...');
      
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }
      
      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      final json = profile.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();

      appLogger.d('   Führe UPDATE via Dio aus...');
      
      // UPDATE via Dio
      final response = await _db.dioClient.patch(
        '/users?id=eq.$userId',
        data: json,
        options: Options(
          headers: {
            'Prefer': 'return=minimal',
          },
        ),
      );
      
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('UPDATE fehlgeschlagen: ${response.statusCode}');
      }

      appLogger.i('✅ Profil erfolgreich aktualisiert');
    } catch (e) {
      appLogger.e('❌ Fehler beim Aktualisieren des Profils: $e');
      rethrow;
    }
  }

  /// Reads just the default exercise-credit factor. A one-column select,
  /// because the day loader wants it once per session and has no use for the
  /// rest of the profile.
  ///
  /// Null means the user never set one. A failed read **throws** rather than
  /// answering null: the two are worlds apart here, since silently reading a
  /// 50% default as "no default" would credit the whole burn and quietly hand
  /// the user hundreds of calories they had asked not to be given.
  Future<double?> getExerciseCreditFactor() async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) {
      throw Exception('Token ungültig');
    }
    final userId = _userId;
    if (userId == null) throw Exception('Keine User-ID verfügbar');

    final response = await _db.client
        .from('users')
        .select('exercise_credit_factor')
        .eq('id', userId)
        .maybeSingle();

    final value = response?['exercise_credit_factor'];
    return value == null ? null : (value as num).toDouble();
  }

  /// Writes just the default exercise-credit factor, [factor] `null` meaning
  /// "back to counting all of it".
  ///
  /// Its own PATCH rather than a field on [updateProfile], because
  /// [UserProfile.toJson] omits nulls: the profile-setup and goal-recommendation
  /// screens send a partial profile that never mentions this factor, and an
  /// explicit null from them would silently clear a setting they never showed.
  /// Here the null is the point, so it is sent on its own.
  Future<void> updateExerciseCreditFactor(double? factor) async {
    final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) throw Exception('Token ungültig');

    final userId = _userId;
    if (userId == null) throw Exception('Keine User-ID verfügbar');

    final response = await _db.dioClient.patch(
      '/users?id=eq.$userId',
      data: {
        'exercise_credit_factor': factor,
        'updated_at': DateTime.now().toIso8601String(),
      },
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Exercise-Credit-Faktor UPDATE fehlgeschlagen: ${response.statusCode}');
    }
    appLogger.i('✅ Exercise-Credit-Faktor gespeichert: ${factor ?? "default"}');
  }
}

