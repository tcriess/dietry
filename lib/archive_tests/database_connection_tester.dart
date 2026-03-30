// Database Connection Tester
import 'neon_database_service.dart';

class DatabaseConnectionTester {
  final NeonDatabaseService _db;
  
  DatabaseConnectionTester(this._db);
  
  /// Teste die Verbindung zur Neon Data API
  Future<Map<String, dynamic>> testConnection() async {
    final results = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'tests': <Map<String, dynamic>>[],
    };
    
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔌 TESTE NEON DATABASE VERBINDUNG');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Test 1: Initialisierung
    try {
      print('📋 Test 1: Database Service Initialisierung...');
      await _db.init();
      print('  ✅ Service initialisiert\n');
      results['tests'].add({
        'name': 'Initialisierung',
        'status': 'success',
      });
    } catch (e) {
      print('  ❌ Fehler: $e\n');
      results['tests'].add({
        'name': 'Initialisierung',
        'status': 'failed',
        'error': e.toString(),
      });
      return results;
    }
    
    // Test 2: Auth-Status
    print('📋 Test 2: Authentifizierungs-Status...');
    print('  JWT vorhanden: ${_db.isAuthenticated}');
    if (!_db.isAuthenticated) {
      print('  ⚠️ Keine Authentifizierung - API-Calls werden fehlschlagen\n');
      results['tests'].add({
        'name': 'Auth-Status',
        'status': 'warning',
        'message': 'Nicht authentifiziert',
      });
    } else {
      print('  ✅ Authentifiziert\n');
      results['tests'].add({
        'name': 'Auth-Status',
        'status': 'success',
      });
    }
    
    // Test 3: Einfacher SELECT auf users
    try {
      print('📋 Test 3: SELECT auf users-Tabelle...');
      final response = await _db.client
        .from('users')
        .select('id, email, name')
        .limit(1);
      
      print('  ✅ Query erfolgreich!');
      print('  📄 Ergebnis: $response');
      print('  📊 Anzahl Zeilen: ${(response as List).length}\n');
      
      results['tests'].add({
        'name': 'SELECT users',
        'status': 'success',
        'rowCount': (response as List).length,
      });
    } catch (e) {
      print('  ❌ Query fehlgeschlagen: $e');
      print('  💡 Mögliche Ursachen:');
      print('     - Tabelle existiert nicht');
      print('     - RLS blockiert Zugriff (keine auth.user_id())');
      print('     - Falsche Data API URL');
      print('     - Keine/falsche Authentifizierung\n');
      
      results['tests'].add({
        'name': 'SELECT users',
        'status': 'failed',
        'error': e.toString(),
      });
    }
    
    // Test 4: SELECT auf nutrition_goals
    try {
      print('📋 Test 4: SELECT auf nutrition_goals-Tabelle...');
      final response = await _db.client
        .from('nutrition_goals')
        .select()
        .limit(5);
      
      print('  ✅ Query erfolgreich!');
      print('  📊 Anzahl Zeilen: ${(response as List).length}\n');
      
      results['tests'].add({
        'name': 'SELECT nutrition_goals',
        'status': 'success',
        'rowCount': (response as List).length,
      });
    } catch (e) {
      print('  ❌ Query fehlgeschlagen: $e\n');
      results['tests'].add({
        'name': 'SELECT nutrition_goals',
        'status': 'failed',
        'error': e.toString(),
      });
    }
    
    // Test 5: SELECT auf food_entries
    try {
      print('📋 Test 5: SELECT auf food_entries-Tabelle...');
      final response = await _db.client
        .from('food_entries')
        .select()
        .limit(5);
      
      print('  ✅ Query erfolgreich!');
      print('  📊 Anzahl Zeilen: ${(response as List).length}\n');
      
      results['tests'].add({
        'name': 'SELECT food_entries',
        'status': 'success',
        'rowCount': (response as List).length,
      });
    } catch (e) {
      print('  ❌ Query fehlgeschlagen: $e\n');
      results['tests'].add({
        'name': 'SELECT food_entries',
        'status': 'failed',
        'error': e.toString(),
      });
    }
    
    // Zusammenfassung
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 ZUSAMMENFASSUNG');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    final tests = results['tests'] as List;
    final successful = tests.where((t) => t['status'] == 'success').length;
    final failed = tests.where((t) => t['status'] == 'failed').length;
    final warnings = tests.where((t) => t['status'] == 'warning').length;
    
    print('✅ Erfolgreich: $successful');
    print('❌ Fehlgeschlagen: $failed');
    print('⚠️  Warnungen: $warnings');
    print('\nGesamtstatus: ${failed == 0 ? "✅ ERFOLGREICH" : "❌ FEHLER"}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    results['summary'] = {
      'successful': successful,
      'failed': failed,
      'warnings': warnings,
      'overallStatus': failed == 0 ? 'success' : 'failed',
    };
    
    return results;
  }
}

