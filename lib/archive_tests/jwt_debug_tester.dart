// JWT Debug Tester - Prüft ob JWT-Token korrekt gesetzt wird
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgrest/postgrest.dart';
import 'neon_database_service.dart';

class JwtDebugTester {
  static const _storage = FlutterSecureStorage();
  
  /// Debug: Prüfe alle gespeicherten JWT-Tokens und Session-Daten
  static Future<void> debugJwtStatus() async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔍 JWT DEBUG STATUS');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Prüfe alle relevanten gespeicherten Tokens
    final tokens = {
      'neon_jwt_token': await _storage.read(key: 'neon_jwt_token'),
      'neon_access_token': await _storage.read(key: 'neon_access_token'),
      'neon_user_id': await _storage.read(key: 'neon_user_id'),
    };
    
    print('📦 Gespeicherte Tokens:');
    for (final entry in tokens.entries) {
      if (entry.value != null) {
        final preview = entry.value!.length > 30 
          ? '${entry.value!.substring(0, 30)}...' 
          : entry.value!;
        print('  ✅ ${entry.key}: $preview');
      } else {
        print('  ❌ ${entry.key}: (nicht vorhanden)');
      }
    }
    print('');
    
    // Test: Initialisiere NeonDatabaseService
    print('🔄 Initialisiere NeonDatabaseService...');
    final dbService = NeonDatabaseService();
    await dbService.init();
    
    if (dbService.isAuthenticated) {
      print('  ✅ Service ist authentifiziert!');
    } else {
      print('  ❌ Service ist NICHT authentifiziert');
      print('  💡 Bitte zuerst einloggen!');
    }
    print('');
    
    // Test: API-Request mit JWT
    if (dbService.isAuthenticated) {
      print('🧪 Teste API-Request mit JWT...');
      try {
        final response = await dbService.client
          .from('users')
          .select('count')
          .count(CountOption.exact);
        
        print('  ✅ API-Request erfolgreich!');
        print('  📊 Response: $response\n');
      } catch (e) {
        final errorStr = e.toString();
        
        if (errorStr.contains('400') && errorStr.contains('missing authentication')) {
          print('  ❌ FEHLER 400: JWT wird nicht übergeben!');
          print('  💡 Lösung: PostgrestClient muss mit JWT neu initialisiert werden\n');
          print('  🔧 FIX in neon_database_service.dart:');
          print('     In setJWT() den PostgrestClient NEU erstellen statt nur Header setzen!\n');
        } else if (errorStr.contains('401')) {
          print('  ❌ FEHLER 401: JWT ist ungültig oder abgelaufen!');
          print('  💡 Lösung: Neu einloggen um neuen JWT zu erhalten\n');
        } else if (errorStr.contains('403')) {
          print('  ❌ FEHLER 403: RLS blockiert Zugriff!');
          print('  💡 Lösung: Anonymous Policies aktivieren (siehe NEON_ANONYMOUS_POLICIES_ANLEITUNG.md)\n');
        } else {
          print('  ❌ Unbekannter Fehler: $e\n');
        }
      }
    } else {
      print('⏭️  Überspringe API-Test (nicht authentifiziert)\n');
    }
    
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🏁 JWT DEBUG ABGESCHLOSSEN');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Gib Empfehlungen
    if (!dbService.isAuthenticated) {
      print('💡 NÄCHSTE SCHRITTE:');
      print('   1. In der App auf "Mit Google anmelden" klicken');
      print('   2. Nach erfolgreichem Login erneut testen\n');
    }
  }
  
  /// Test: API-Verbindung MIT JWT-Token
  static Future<void> testWithJwt() async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔌 TESTE NEON DATA API MIT JWT');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    final dbService = NeonDatabaseService();
    await dbService.init();
    
    if (!dbService.isAuthenticated) {
      print('❌ Nicht authentifiziert!');
      print('💡 Bitte zuerst einloggen (Mit Google anmelden)\n');
      return;
    }
    
    print('✅ Authentifiziert! Teste Tabellen...\n');
    
    final tables = ['users', 'nutrition_goals', 'food_entries'];
    
    for (final table in tables) {
      try {
        print('📋 Test: Tabelle "$table"...');
        
        final response = await dbService.client
          .from(table)
          .select('*')
          .limit(1);
        
        print('  ✅ Erfolgreich!');
        print('  📊 Zeilen: ${(response as List).length}\n');
      } catch (e) {
        final errorStr = e.toString();
        
        if (errorStr.contains('400')) {
          print('  ❌ FEHLER 400: JWT wird nicht übergeben!');
          print('  🔧 PostgrestClient muss neu initialisiert werden!\n');
        } else if (errorStr.contains('401')) {
          print('  ❌ FEHLER 401: JWT ungültig!');
          print('  💡 Neu einloggen erforderlich\n');
        } else if (errorStr.contains('403')) {
          print('  ⚠️  FEHLER 403: RLS blockiert!');
          print('  💡 Anonymous Policies aktivieren für Tests\n');
        } else {
          print('  ❌ Fehler: $e\n');
        }
      }
    }
    
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🏁 TEST ABGESCHLOSSEN');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }
}

