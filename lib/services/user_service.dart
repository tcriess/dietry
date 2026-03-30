import 'neon_database_service.dart';

/// Service für User-Management in der Datenbank
class UserService {
  final NeonDatabaseService _dbService;
  
  UserService(this._dbService);
  
  /// Prüft ob User existiert und legt ihn bei Bedarf an.
  /// Verwendet die RPC-Funktion upsert_user (SECURITY DEFINER) damit
  /// der "same email, new id"-Fall (Neon Auth regenerated sub) sicher
  /// behandelt wird, ohne RLS-Einschränkungen.
  Future<Map<String, dynamic>> ensureUserExists({
    required String userId,
    required String email,
    String? name,
  }) async {
    try {
      final result = await _dbService.client.rpc('upsert_user', params: {
        'p_id': userId,
        'p_email': email,
        if (name != null) 'p_name': name,
      });

      // rpc() returns a list for RETURNS SETOF
      final rows = result as List;
      if (rows.isNotEmpty) {
        print('✅ User upserted: $email');
        return rows.first as Map<String, dynamic>;
      }

      // Fallback: fetch by id (should not normally be needed)
      final fetched = await _dbService.client
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      return fetched;
    } catch (e) {
      print('❌ Fehler beim User-Management: $e');
      rethrow;
    }
  }
  
  /// Holt User-Daten aus der Datenbank
  Future<Map<String, dynamic>?> getUser(String userId) async {
    try {
      final users = await _dbService.client
          .from('users')
          .select()
          .eq('id', userId)
          .limit(1);
      
      if (users.isEmpty) {
        return null;
      }
      
      return users.first;
    } catch (e) {
      print('❌ Fehler beim Laden des Users: $e');
      return null;
    }
  }
  
  /// Aktualisiert User-Daten
  Future<Map<String, dynamic>> updateUser({
    required String userId,
    String? name,
    String? email,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (email != null) updates['email'] = email;
      
      updates['updated_at'] = DateTime.now().toIso8601String();
      
      // Nutze updateUserData Helper-Methode (vermeidet Prefer-Header-Problem)
      await _dbService.updateUserData(userId: userId, updates: updates);
      
      // Lade den aktualisierten User
      final updated = await _dbService.client
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      
      print('✅ User aktualisiert: $email');
      return updated;
      
    } catch (e) {
      print('❌ Fehler beim Aktualisieren des Users: $e');
      rethrow;
    }
  }
}

