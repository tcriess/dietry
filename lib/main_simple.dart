import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;

// Services
import 'services/neon_auth_service.dart';
import 'services/app_logger.dart';

void main() {
  runApp(const DietryApp());
}

class DietryApp extends StatefulWidget {
  const DietryApp({super.key});

  @override
  State<DietryApp> createState() => _DietryAppState();
}

class _DietryAppState extends State<DietryApp> {
  late final NeonAuthService _authService;
  bool _handledVerifier = false;

  @override
  void initState() {
    super.initState();
    _authService = NeonAuthService();
    
    // ✅ WICHTIG: Bei App-Start nach Verifier in URL suchen
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleOAuthCallback();
      });
    }
  }

  /// Prüft URL auf neon_auth_session_verifier und holt Session
  Future<void> _handleOAuthCallback() async {
    if (_handledVerifier) return;
    
    final uri = Uri.base;
    final verifier = uri.queryParameters['neon_auth_session_verifier'];
    
    if (verifier != null && verifier.isNotEmpty) {
      _handledVerifier = true;
      
      appLogger.d('🔑 Found verifier in URL, getting session...');
      
      final success = await _authService.getSessionWithVerifier(verifier);
      
      if (success) {
        appLogger.d('✅ Session established successfully');
        
        // URL bereinigen (Verifier entfernen)
        _cleanUrl();
      } else {
        appLogger.d('❌ Failed to establish session');
      }
    }
  }

  /// Entfernt den Verifier-Parameter aus der URL
  void _cleanUrl() {
    if (!kIsWeb) return;
    
    try {
      final uri = Uri.base;
      final params = Map<String, String>.from(uri.queryParameters);
      params.remove('neon_auth_session_verifier');
      
      final newUri = uri.replace(queryParameters: params.isEmpty ? null : params);
      
      // URL ohne Reload aktualisieren
      web.window.history.replaceState(null, '', newUri.toString());
      
      appLogger.d('🧹 Cleaned URL');
    } catch (e) {
      appLogger.d('⚠️ Error cleaning URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dietry',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: AnimatedBuilder(
        animation: _authService,
        builder: (context, child) {
          if (_authService.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          
          if (_authService.isLoggedIn) {
            return HomeScreen(authService: _authService);
          }
          
          return LoginScreen(authService: _authService);
        },
      ),
    );
  }
}

/// Login Screen mit OAuth
class LoginScreen extends StatelessWidget {
  final NeonAuthService authService;
  
  const LoginScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.restaurant, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Dietry',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Dein Ernährungstagebuch'),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Mit Google anmelden'),
              onPressed: () => _handleGoogleLogin(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGoogleLogin(BuildContext context) async {
    try {
      // ✅ Callback-URL ist die Haupt-App selbst!
      final callbackUrl = kIsWeb 
          ? Uri.base.origin  // Web: Current origin
          : 'http://localhost:8080/callback';  // Desktop: Local server
      
      appLogger.d('🚀 Starting OAuth with callback: $callbackUrl');
      
      // Starte OAuth Flow
      final oauthUrl = await authService.startOAuthFlow(
        provider: 'google',
        callbackUrl: callbackUrl,
      );
      
      // Öffne OAuth URL im Browser
      final uri = Uri.parse(oauthUrl);
      if (await canLaunchUrl(uri)) {
        // Im gleichen Tab öffnen (wichtig für Cookie-Handling!)
        await launchUrl(uri, mode: LaunchMode.platformDefault);
        
        // Nach OAuth Redirect kommt der User zurück zur App
        // mit ?neon_auth_session_verifier=XXX in der URL
        // Das wird von _handleOAuthCallback() beim App-Start verarbeitet
        
      } else {
        throw Exception('Could not launch OAuth URL');
      }
      
    } catch (e) {
      appLogger.d('❌ Login error: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Home Screen - Zeigt Ernährungsdaten
class HomeScreen extends StatelessWidget {
  final NeonAuthService authService;
  
  const HomeScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    final user = authService.session?['user'] as Map<String, dynamic>?;
    final email = user?['email'] as String? ?? 'Unbekannt';
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dietry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Erfolgreich angemeldet!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Email: $email'),
            const SizedBox(height: 24),
            if (authService.jwt != null) ...[
              const Text('JWT vorhanden ✅'),
              const SizedBox(height: 8),
              Text(
                'JWT: ${authService.jwt!.substring(0, 30)}...',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ] else
              const Text('Kein JWT ⚠️', style: TextStyle(color: Colors.orange)),
          ],
        ),
      ),
    );
  }
}

