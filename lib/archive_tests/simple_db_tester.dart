// Test-Utility: Teste DB-Verbindung ohne Authentifizierung
// Nur für Entwicklung/Debugging!

import 'package:postgrest/postgrest.dart';

class SimpleDbTester {
  static const String dataApiUrl =
    'https://ep-fragrant-sea-al0lc06o.apirest.c-3.eu-central-1.aws.neon.tech/dietry/rest/v1';
  
  /// Teste Basis-Verbindung zur Data API (ohne Auth)
  static Future<void> testBasicConnection() async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔌 TESTE NEON DATA API VERBINDUNG (ohne Auth)');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    final client = PostgrestClient(dataApiUrl);
    
    // Test 1: Prüfe ob API erreichbar ist
    try {
      print('📋 Test 1: API Erreichbarkeit...');
      print('   URL: $dataApiUrl');
      
      // Versuche einen einfachen Request
      final response = await client
        .from('users')
        .select('count')
        .count(CountOption.exact);
      
      print('  ✅ API ist erreichbar!');
      print('  📄 Response-Typ: ${response.runtimeType}');
      print('  📊 Daten: $response\n');
    } catch (e) {
      print('  ❌ Fehler: $e');
      print('  💡 Mögliche Ursachen:');
      print('     - Falsche Data API URL');
      print('     - Data API nicht aktiviert in Neon Console');
      print('     - Netzwerkproblem\n');
      
      if (e.toString().contains('401') || e.toString().contains('403')) {
        print('  ℹ️  401/403 Fehler bedeutet: API erreichbar, aber Auth fehlt');
        print('     Das ist OK - die Verbindung funktioniert!\n');
      }
    }
    
    // Test 2: Prüfe einzelne Tabellen
    final tables = ['users', 'nutrition_goals', 'food_entries'];
    
    for (final table in tables) {
      try {
        print('📋 Test: Tabelle "$table"...');
        
        final response = await client
          .from(table)
          .select('*')
          .limit(1);
        
        print('  ✅ Tabelle existiert und ist lesbar!');
        print('  📊 Zeilen: ${(response as List).length}\n');
      } catch (e) {
        final errorStr = e.toString();
        
        if (errorStr.contains('401') || errorStr.contains('403')) {
          print('  ⚠️  Auth erforderlich (401/403) - Tabelle existiert!');
          print('     RLS ist aktiv und blockiert unauthentifizierte Zugriffe.\n');
        } else if (errorStr.contains('404') || errorStr.contains('not found')) {
          print('  ❌ Tabelle existiert nicht!');
          print('     Bitte erstelle die Tabelle in der Neon Console.\n');
        } else {
          print('  ❌ Fehler: $e\n');
        }
      }
    }
    
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🏁 BASIS-TEST ABGESCHLOSSEN');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    print('💡 NÄCHSTER SCHRITT:');
    print('   Wenn Tests "401/403" zeigen → DB-Verbindung OK!');
    print('   Wenn Tests "404" zeigen → Tabellen fehlen!');
    print('   Dann: Cookie-Sharing implementieren für Auth\n');
  }
}

