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
          .select('id, birthdate, height, gender, activity_level, weight_goal')
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
}

