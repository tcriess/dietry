// Test-Utility: Teste Better Auth Session-Endpoints nach dem Login
// Diese Datei hilft zu verstehen, welches Token-Format Better Auth nutzt

import 'package:dio/dio.dart';

class SessionTester {
  static const String authBaseUrl = 
    'https://ep-fragrant-sea-al0lc06o.neonauth.c-3.eu-central-1.aws.neon.tech/neondb/auth';
  
  /// Teste alle möglichen Session-Endpunkte
  /// Rufe diese Funktion nach erfolgreichem Login auf
  static Future<void> testSessionEndpoints({String? sessionToken}) async {
    final dio = Dio();
    
    final endpoints = [
      '/api/auth/get-session',  // Laut Neon Docs: Der korrekte Endpoint!
      '/session',
      '/get-session',
      '/api/session',
      '/api/auth/session',
      '/user',
      '/api/user',
      '/api/auth/user',
    ];
    
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔍 TESTE BETTER AUTH SESSION-ENDPOINTS');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    for (final endpoint in endpoints) {
      try {
        print('📡 GET $authBaseUrl$endpoint');
        
        final response = await dio.get(
          '$authBaseUrl$endpoint',
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (sessionToken != null) 'Authorization': 'Bearer $sessionToken',
            },
          ),
        );
        
        print('  ✅ Status: ${response.statusCode}');
        print('  📄 Response: ${response.data}');
        print('  🍪 Cookies: ${response.headers['set-cookie']}');
        
        // Analysiere Response
        final data = response.data;
        if (data is Map) {
          if (data.containsKey('session')) {
            print('  🎯 Enthält "session": ${data['session']}');
          }
          if (data.containsKey('token')) {
            print('  🎯 Enthält "token": ${data['token']}');
          }
          if (data.containsKey('user')) {
            print('  🎯 Enthält "user": ${data['user']}');
          }
          if (data.containsKey('accessToken')) {
            print('  🎯 Enthält "accessToken": ${data['accessToken']}');
          }
        }
        print('');
        
      } catch (e) {
        if (e is DioException) {
          print('  ❌ Status: ${e.response?.statusCode ?? "Keine Response"}');
          print('  📄 Error: ${e.response?.data ?? e.message}');
        } else {
          print('  ❌ Error: $e');
        }
        print('');
      }
    }
    
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🏁 TEST ABGESCHLOSSEN');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }
  
  /// Prüfe, ob Cookies gesetzt wurden
  static Future<void> inspectCookies() async {
    print('\n🍪 COOKIES INSPECTION:');
    print('Hinweis: Better Auth nutzt httpOnly Cookies, die nicht');
    print('direkt von Dart aus gelesen werden können.');
    print('Cookies werden automatisch vom Browser/WebView mitgesendet.\n');
  }
}

