import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/neon_database_service.dart';
import '../services/jwt_helper.dart';

/// Tester für automatische User-Erstellung
class UserCreationTester {
  
  /// Testet die automatische User-Erstellung
  static Future<void> testUserCreation() async {
    print('\n🧪 ===== USER CREATION TEST =====\n');
    
    try {
      final dbService = NeonDatabaseService();
      await dbService.init();
      
      // Prüfe ob JWT vorhanden
      if (dbService.userId == null) {
        print('⚠️ Kein User eingeloggt - kann User-Creation nicht testen');
        print('   Bitte zuerst einloggen!');
        return;
      }
      
      print('✅ Test-Setup:');
      print('   User-ID: ${dbService.userId}');
      print('   Authentifiziert: ${dbService.isAuthenticated}');
      
      // Prüfe ob User in DB existiert
      print('\n📊 Prüfe User in Datenbank...');
      final users = await dbService.client
          .from('users')
          .select()
          .eq('id', dbService.userId!)
          .limit(1);
      
      if (users.isEmpty) {
        print('❌ User NICHT in Datenbank gefunden!');
        print('   Das sollte nicht passieren - automatische Erstellung hat nicht funktioniert');
      } else {
        final user = users.first;
        print('✅ User in Datenbank gefunden!');
        print('   ID: ${user['id']}');
        print('   Email: ${user['email']}');
        print('   Name: ${user['name'] ?? '(nicht gesetzt)'}');
        print('   Erstellt: ${user['created_at']}');
      }
      
      print('\n✅ User Creation Test abgeschlossen!');
      
    } catch (e) {
      print('❌ Fehler beim User Creation Test: $e');
      print('   Stack: $e');
    }
    
    print('\n🧪 ===== TEST ENDE =====\n');
  }
  
  /// Debug: Zeige JWT-Inhalt
  static void debugJWT() async {
    print('\n🔍 ===== JWT DEBUG =====\n');
    
    final dbService = NeonDatabaseService();
    await dbService.init();
    
    // Hole JWT aus Storage
    const storage = FlutterSecureStorage();
    final jwt = await storage.read(key: 'neon_jwt_token');
    
    if (jwt == null) {
      print('❌ Kein JWT im Storage');
      return;
    }
    
    print('✅ JWT gefunden');
    print('   Länge: ${jwt.length} Zeichen');
    print('');
    
    // Dekodiere und zeige Claims
    JwtHelper.debugToken(jwt);
    
    print('\n🔍 ===== DEBUG ENDE =====\n');
  }
}


