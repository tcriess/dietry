import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show MethodChannel, TextInput;
import 'package:shared_preferences/shared_preferences.dart';
import 'main_web_imports_web.dart' if (dart.library.io) 'main_web_imports.dart' as html;
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'platform_utils.dart' as platform;
import 'l10n/app_localizations.dart';


import 'package:dietry_cloud/dietry_cloud.dart';

// Services
import 'app_features.dart';
import 'services/neon_database_service.dart';
import 'services/neon_auth_service.dart' show NeonAuthService, EmailVerificationPendingException;
import 'services/nutrition_goal_service.dart';
import 'services/jwt_helper.dart';
import 'services/data_store.dart';
import 'services/sync_service.dart';
import 'services/water_intake_service.dart';
import 'services/water_reminder_service.dart';
import 'services/cheat_day_service.dart';
import 'app_config.dart';
import 'services/server_config_service.dart';

// Models
import 'models/models.dart';

// Screens
import 'screens/goal_recommendation_screen.dart';
import 'screens/food_entries_list_screen.dart';
import 'screens/activities_list_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/info_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // sqflite needs FFI on Linux/Windows/macOS desktop (not web, not Android/iOS)
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Load any user-configured server URLs before services start.
  await ServerConfigService.loadIntoCache();

  // Web: Auth-Base-URL in localStorage schreiben, damit auth_callback.html
  // dieselbe URL verwendet wie die Flutter-App (verhindert Cookie-Domain-Mismatch).
  if (kIsWeb) {
    html.setToLocalStorage(
      'dietry_auth_base_url', ServerConfigService.effectiveAuthBaseUrl);
  }

  await WaterReminderService.initialize();

  runApp(const AuthApp());
}


// Widget für den Auth-Dialog mit WebView (für OAuth-Redirect-URL)
class NeonAuthWebViewDialog extends StatefulWidget {
  final String authUrl; // OAuth-Redirect-URL vom Auth-Server
  final String callbackUrl; // Erwartete Callback-URL
  const NeonAuthWebViewDialog({
    super.key, 
    required this.authUrl, 
    required this.callbackUrl,
  });

  @override
  State<NeonAuthWebViewDialog> createState() => _NeonAuthWebViewDialogState();
}

class _NeonAuthWebViewDialogState extends State<NeonAuthWebViewDialog> {
  bool _loading = true;
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (nav) {
          final url = nav.url;
          final uri = Uri.parse(url);
          
          if (uri.queryParameters.containsKey('neon_auth_session_verifier')) {
            final verifier = uri.queryParameters['neon_auth_session_verifier'];
            Navigator.of(context).pop({'success': true, 'verifier': verifier});
            return NavigationDecision.prevent;
          }
          
          return NavigationDecision.navigate;
        },
        onPageFinished: (url) {
          setState(() => _loading = false);
          
          final uri = Uri.parse(url);
          if (uri.queryParameters.containsKey('neon_auth_session_verifier')) {
            final verifier = uri.queryParameters['neon_auth_session_verifier'];
            Navigator.of(context).pop({'success': true, 'verifier': verifier});
          }
        },
      ));
    _controller.loadRequest(Uri.parse(widget.authUrl));
  }


  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        width: 400,
        height: 600,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

// LoginScreen mit Google-Login (Neon Auth)
class LoginScreen extends StatelessWidget {
  final NeonAuthService authService;
  final NeonDatabaseService dbService;
  final void Function(Locale?)? onLocaleChanged;
  const LoginScreen({
    super.key,
    required this.authService,
    required this.dbService,
    this.onLocaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: onLocaleChanged != null
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                PopupMenuButton<Locale?>(
                  icon: const Icon(Icons.language),
                  onSelected: onLocaleChanged,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: Locale('de'), child: Text('🇩🇪  Deutsch')),
                    PopupMenuItem(value: Locale('en'), child: Text('🇬🇧  English')),
                    PopupMenuItem(value: Locale('es'), child: Text('🇪🇸  Español')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: null, child: Text('⚙️  System')),
                  ],
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (AppConfig.isDevelopment)
              Container(
                width: double.infinity,
                color: Colors.orange.shade700,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: Text(
                  l.devBannerText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // Logo
              CircleAvatar(
                radius: 48,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.restaurant_menu,
                  size: 52,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.appTitle,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.appSubtitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Features
              _FeatureRow(
                icon: Icons.track_changes,
                title: l.featureTrackTitle,
                subtitle: l.featureTrackSubtitle,
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: Icons.search,
                title: l.featureDatabaseTitle,
                subtitle: l.featureDatabaseSubtitle,
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: Icons.directions_run,
                title: l.featureActivitiesTitle,
                subtitle: l.featureActivitiesSubtitle,
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: Icons.flag_outlined,
                title: l.featureGoalsTitle,
                subtitle: l.featureGoalsSubtitle,
              ),

              const SizedBox(height: 40),

              // Login Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text(l.loginWithGoogle),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                  onPressed: () async {
                try {
                  // WEB: Redirect zu auth_callback.html (übernimmt kompletten OAuth-Flow)
                  if (kIsWeb) {
                    html.browserRedirect('/auth_callback.html');
                    return;
                  }
                  
                  // NATIVE: Plattform-spezifischer OAuth-Flow
                  String callbackUrl;
                  Completer<String>? desktopCallbackCompleter;
                  
                  if (platform.isAndroid()) {
                    callbackUrl = AppConfig.androidCallbackUrl;
                  } else if (platform.isLinux() || platform.isWindows()) {
                    // Desktop: Lokaler HTTP-Server auf einem freien Port.
                    // Port 0 lässt das OS einen freien Port wählen — kein Konflikt
                    // mit anderen Diensten möglich.
                    desktopCallbackCompleter = Completer<String>();

                    final handler = (shelf.Request request) async {
                      if (request.url.path == 'callback') {
                        final verifier = request.url.queryParameters['neon_auth_session_verifier'];
                        if (verifier != null && !desktopCallbackCompleter!.isCompleted) {
                          desktopCallbackCompleter.complete(verifier);
                          return shelf.Response.ok(
                            '<html lang="de"><body><h1>Login erfolgreich!</h1><p>Sie können dieses Fenster schließen.</p></body></html>',
                            headers: {'Content-Type': 'text/html'},
                          );
                        }
                      }
                      return shelf.Response.notFound('Not found');
                    };

                    // Port 0 → OS assigns a free port; read it back via server.port.
                    final server = await shelf_io.serve(handler, 'localhost', 0);
                    callbackUrl = 'http://localhost:${server.port}/callback';
                    desktopCallbackCompleter!.future.timeout(
                      const Duration(minutes: 5),
                      onTimeout: () => '',
                    ).whenComplete(() => server.close());
                  } else {
                    // iOS/macOS: Custom Scheme für WebView
                    callbackUrl = 'com.sws.dietry://auth.callback';
                  }
                  
                  // ✅ Starte OAuth-Flow via NeonAuthService
                  final redirectUrl = await authService.startOAuthFlow(
                    provider: 'google',
                    callbackUrl: callbackUrl,
                  );
                  
                  print('🔗 OAuth URL: $redirectUrl');
                  

                  // Öffne OAuth-URL (plattformabhängig)
                  if (platform.isAndroid()) {
                    // Android: Browser öffnen, Callback via App Link
                    // (Challenge-Cookie wird von NeonAuthService verwaltet)
                    
                    if (!await launchUrl(Uri.parse(redirectUrl), mode: LaunchMode.externalApplication)) {
                      throw Exception('Konnte Browser nicht öffnen');
                    }
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bitte schließen Sie die Authentifizierung im Browser ab...'),
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }
                    return;
                  } else if (platform.isLinux() || platform.isWindows()) {
                    // Desktop: HTTP Server + Browser
                    if (!await launchUrl(Uri.parse(redirectUrl), mode: LaunchMode.externalApplication)) {
                      throw Exception('Konnte Browser nicht öffnen');
                    }
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bitte schließen Sie die Authentifizierung im Browser ab...'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                    
                    final verifier = await desktopCallbackCompleter!.future.timeout(
                      const Duration(minutes: 5),
                      onTimeout: () => throw Exception('Login-Timeout'),
                    );
                    
                    if (verifier.isNotEmpty) {
                      // ✅ Nutze NeonAuthService für Session-Exchange
                      final success = await authService.getSessionWithVerifier(verifier);
                      
                      if (success && authService.jwt != null) {
                        // Setze JWT im GLOBALEN Database Service
                        // Zugriff via findAncestorStateOfType
                        final authAppState = context.findAncestorStateOfType<_AuthAppState>();
                        if (authAppState != null) {
                          await authAppState._dbService?.setJWT(authService.jwt!);
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Login erfolgreich: ${authService.session?['user']?['email'] ?? ''}'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } else {
                        throw Exception('Session-Exchange fehlgeschlagen');
                      }
                    }
                  } else {
                    // iOS/macOS: WebView Dialog
                    final session = await showDialog<Map<String, dynamic>>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => NeonAuthWebViewDialog(
                        authUrl: redirectUrl,
                        callbackUrl: callbackUrl,
                      ),
                    );

                    if (session?['success'] == true) {
                      final verifier = session?['verifier'] as String?;
                      if (verifier != null) {
                        // ✅ Nutze NeonAuthService für Session-Exchange
                        final success = await authService.getSessionWithVerifier(verifier);

                        if (success && authService.jwt != null) {
                          // Setze JWT im GLOBALEN Database Service
                          final authAppState = context.findAncestorStateOfType<_AuthAppState>();
                          if (authAppState != null) {
                            await authAppState._dbService?.setJWT(authService.jwt!);
                          }
                          
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Login erfolgreich: ${authService.session?['user']?['email'] ?? ''}'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } else {
                          throw Exception('Session-Exchange fehlgeschlagen');
                        }
                      }
                    } else {
                      throw Exception('Authentifizierung wurde abgebrochen');
                    }
                  }
                } catch (e) {
                  print('❌ Login fehlgeschlagen: $e');
                  if (context.mounted) {
                    final lErr = AppLocalizations.of(context)!;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(lErr.loginFailed(e.toString())),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              },
            ),
            ),   // SizedBox

            const SizedBox(height: 16),

            // Divider
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    l.orContinueWith,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),

            const SizedBox(height: 12),

            // Email / Password login
            _EmailLoginSection(
              authService: authService,
              dbService: dbService,
            ),

            const SizedBox(height: 20),

            // Datenschutz-Hinweis
            Text(
              l.privacyNote,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InfoScreen()),
              ),
              child: Text(l.impressumLink, style: const TextStyle(fontSize: 12)),
            ),

            // Self-hosted server config (CE only)
            if (!AppConfig.isCloudEdition)
              TextButton.icon(
                icon: const Icon(Icons.dns_outlined, size: 16),
                label: Text(l.serverConfigButton, style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                ),
                onPressed: () async {
                  final changed = await showDialog<bool>(
                    context: context,
                    builder: (_) => const _ServerConfigDialog(),
                  );
                  if (changed == true && context.mounted) {
                    // Update the auth_callback.html localStorage entry on web
                    if (kIsWeb) {
                      html.setToLocalStorage(
                        'dietry_auth_base_url',
                        ServerConfigService.effectiveAuthBaseUrl,
                      );
                    }
                  }
                },
              ),
          ],
        ),
      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Server configuration dialog (CE / self-hosted only) ──────────────────────

class _ServerConfigDialog extends StatefulWidget {
  const _ServerConfigDialog();

  @override
  State<_ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<_ServerConfigDialog> {
  final _dataApiCtrl = TextEditingController();
  final _authBaseCtrl = TextEditingController();
  bool _loading = true;
  bool _hasCustom = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final d = prefs.getString('server_config_data_api_url') ?? '';
    final a = prefs.getString('server_config_auth_base_url') ?? '';
    // Fall back to compiled defaults when fields are empty
    _dataApiCtrl.text = d.isNotEmpty ? d : AppConfig.dataApiUrl;
    _authBaseCtrl.text = a.isNotEmpty ? a : AppConfig.authBaseUrl;
    setState(() {
      _hasCustom = d.isNotEmpty || a.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final dataUrl = _dataApiCtrl.text.trim();
    final authUrl = _authBaseCtrl.text.trim();
    await ServerConfigService.save(dataApiUrl: dataUrl, authBaseUrl: authUrl);
    ServerConfigService.updateCache(dataApiUrl: dataUrl, authBaseUrl: authUrl);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _reset() async {
    await ServerConfigService.reset();
    ServerConfigService.updateCache(dataApiUrl: '', authBaseUrl: '');
    if (mounted) {
      _dataApiCtrl.text = AppConfig.dataApiUrl;
      _authBaseCtrl.text = AppConfig.authBaseUrl;
      setState(() => _hasCustom = false);
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _dataApiCtrl.dispose();
    _authBaseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.dns_outlined),
          const SizedBox(width: 8),
          Text(l.serverConfigTitle),
        ],
      ),
      content: _loading
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.serverConfigDescription,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _dataApiCtrl,
                    decoration: InputDecoration(
                      labelText: l.serverConfigDataApiUrl,
                      hintText: AppConfig.dataApiUrl,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _authBaseCtrl,
                    decoration: InputDecoration(
                      labelText: l.serverConfigAuthBaseUrl,
                      hintText: AppConfig.authBaseUrl,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                  if (_hasCustom) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.serverConfigCustomActive,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: _loading
          ? null
          : [
              if (_hasCustom)
                TextButton(
                  onPressed: _reset,
                  child: Text(l.serverConfigReset),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: _save,
                child: Text(l.save),
              ),
            ],
    );
  }
}

// ── Email / Password login section ───────────────────────────────────────────

class _EmailLoginSection extends StatefulWidget {
  final NeonAuthService authService;
  final NeonDatabaseService dbService;

  const _EmailLoginSection({required this.authService, required this.dbService});

  @override
  State<_EmailLoginSection> createState() => _EmailLoginSectionState();
}

class _EmailLoginSectionState extends State<_EmailLoginSection> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _pendingVerificationEmail;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _forgotPassword() async {
    final l = AppLocalizations.of(context)!;
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final formKey = GlobalKey<FormState>();
    String? sentToEmail;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (sentToEmail != null) {
            return AlertDialog(
              title: Text(l.resetLinkSent),
              content: Text(l.resetLinkSentBody(sentToEmail!)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l.emailVerificationBack),
                ),
              ],
            );
          }
          return AlertDialog(
            title: Text(l.resetPasswordTitle),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: emailCtrl,
                decoration: InputDecoration(
                  labelText: l.emailLabel,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? l.requiredField : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  try {
                    await widget.authService
                        .requestPasswordReset(emailCtrl.text.trim());
                    setDialogState(() => sentToEmail = emailCtrl.text.trim());
                  } catch (e) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.red,
                      ));
                    }
                  }
                },
                child: Text(l.sendResetLink),
              ),
            ],
          );
        },
      ),
    );
    emailCtrl.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final bool success;
      if (_isSignUp) {
        success = await widget.authService.signUpWithEmail(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          name: _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : null,
        );
      } else {
        success = await widget.authService.signInWithEmail(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }

      if (success && widget.authService.jwt != null && mounted) {
        final authAppState = context.findAncestorStateOfType<_AuthAppState>();
        await authAppState?._dbService?.setJWT(widget.authService.jwt!);
      }
    } on EmailVerificationPendingException catch (e) {
      if (mounted) setState(() => _pendingVerificationEmail = e.email);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.loginFailed(e.toString())),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_pendingVerificationEmail != null) {
      return Column(
        children: [
          const Icon(Icons.mark_email_unread_outlined, size: 48, color: Colors.green),
          const SizedBox(height: 16),
          Text(l.emailVerificationTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l.emailVerificationBody(_pendingVerificationEmail!),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() {
              _pendingVerificationEmail = null;
              _isSignUp = false;
            }),
            child: Text(l.emailVerificationBack),
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
        children: [
          if (_isSignUp) ...[
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: l.nameOptionalLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_outline),
              ),
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _emailCtrl,
            decoration: InputDecoration(
              labelText: l.emailLabel,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || !v.contains('@')) ? l.requiredField : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordCtrl,
            decoration: InputDecoration(
              labelText: l.passwordLabel,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            autofillHints: _isSignUp
                ? const [AutofillHints.newPassword]
                : const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              TextInput.finishAutofillContext();
              _submit();
            },
            validator: (v) {
              if (v == null || v.isEmpty) return l.requiredField;
              if (_isSignUp && v.length < 8) return l.passwordTooShort;
              return null;
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : () {
                TextInput.finishAutofillContext();
                _submit();
              },
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_isSignUp ? Icons.person_add : Icons.login),
              label: Text(_isSignUp ? l.signUpWithEmail : l.loginWithEmail),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          if (!_isSignUp)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPassword,
                child: Text(l.forgotPassword, style: const TextStyle(fontSize: 13)),
              ),
            ),
          TextButton(
            onPressed: () => setState(() => _isSignUp = !_isSignUp),
            child: Text(_isSignUp ? l.alreadyHaveAccount : l.noAccount,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
        ),
      ),
    );
  }
}

class AuthApp extends StatefulWidget {
  const AuthApp({super.key});
  @override
  State<AuthApp> createState() => _AuthAppState();
}

class _AuthAppState extends State<AuthApp> with WidgetsBindingObserver {
  late final NeonAuthService _authService;
  NeonDatabaseService? _dbService;
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _authService = NeonAuthService();
    _authService.addListener(_onAuthChanged);
    
    // Initialisiere Database Service mit Token-Refresh-Callback
    _initDatabaseService();
    
    // Registriere App Lifecycle Observer
    WidgetsBinding.instance.addObserver(this);
    
    // ✅ Prüfe OAuth-Callback nur für Native Apps (Android Deep Links)
    // Web-Apps verwenden auth_callback.html und setzen JWT direkt in localStorage
    if (!kIsWeb) {
      _checkOAuthCallback();
    } else {
      // Web: Prüfe localStorage auf JWT (von auth_callback.html gesetzt)
      _checkWebJWT();
    }
  }
  
  Future<void> _initDatabaseService() async {
    final db = NeonDatabaseService();
    _dbService = db;

    // ✅ WICHTIG: Setze Token-Refresh-Callback VOR init()
    db.onTokenExpired = () async {
      print('🔄 Token-Refresh-Callback aufgerufen...');
      final success = await _authService.refreshToken();
      if (success) {
        print('✅ Token erfolgreich refreshed via NeonAuthService');
        return _authService.jwt;
      } else {
        print('❌ Token-Refresh fehlgeschlagen - Logout erforderlich');
        await _authService.signOut();
        return null;
      }
    };

    await db.init();

    // ✅ WICHTIG: Warte bis AuthService fertig geladen hat
    // NeonAuthService lädt Token asynchron im Konstruktor
    while (_authService.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Jetzt JWT setzen wenn vorhanden
    if (_authService.jwt != null) {
      try {
        print('🔑 Setze JWT im DB-Service nach Auth-Init: ${_authService.jwt!.substring(0, 20)}...');
        await db.setJWT(_authService.jwt!);
      } catch (e) {
        print('⚠️ Fehler beim Setzen des JWT: $e');
      }
    } else {
      print('ℹ️ Kein JWT im AuthService - User ist nicht eingeloggt');
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService.removeListener(_onAuthChanged);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed && platform.isAndroid()) {
      _checkOAuthCallback();
    }
  }
  
  Future<void> _checkWebJWT() async {
    try {
      // ✅ WICHTIG: Warte bis AuthService fertig geladen hat
      // AuthService lädt JWT aus SecureStorage im Konstruktor
      while (_authService.isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      print('🔍 AuthService initialisiert, prüfe Web-JWT...');
      
      final jwtFromStorage = html.getFromLocalStorage('neon_jwt');
      
      if (jwtFromStorage != null && jwtFromStorage.isNotEmpty) {
        print('🔍 JWT in localStorage gefunden, validiere...');
        
        // Prüfe ob JWT gültig ist BEVOR wir es verwenden
        final isValid = JwtHelper.decodeToken(jwtFromStorage) != null;
        final isExpired = isValid ? JwtHelper.isTokenExpired(jwtFromStorage) : true;
        
        if (!isValid || isExpired) {
          print('❌ JWT in localStorage ist ungültig oder abgelaufen');
          print('   Cleane localStorage UND FlutterSecureStorage...');
          
          // ✅ Cleane localStorage (Web)
          html.removeFromLocalStorage('neon_jwt');
          html.removeFromLocalStorage('neon_user_email');
          html.removeFromLocalStorage('neon_session_id');
          
          // ✅ Cleane FlutterSecureStorage MANUELL (nicht nur signOut)
          final storage = const FlutterSecureStorage();
          await storage.delete(key: 'neon_jwt');
          await storage.delete(key: 'neon_session');
          await storage.delete(key: 'neon_cookie');
          
          // ✅ Logout im AuthService
          await _authService.signOut();
          
          print('✅ Alle Storages geleert - bereit für Neu-Login');
          return;
        }
        
        print('✅ JWT ist gültig, setze in AuthService UND DB-Service...');
        
        // ✅ WICHTIG: Setze JWT im AuthService (für isLoggedIn)
        await _authService.setJWT(jwtFromStorage);
        
        // ✅ Setze auch im DB-Service (für Datenbank-Zugriff)
        await _dbService?.setJWT(jwtFromStorage);
        
        print('✅ JWT in beiden Services gesetzt - User sollte eingeloggt sein');
      } else {
        print('ℹ️ Kein JWT in localStorage - prüfe SecureStorage...');
        
        // Falls AuthService ein JWT aus SecureStorage geladen hat, validiere es
        if (_authService.jwt != null) {
          print('🔍 JWT in SecureStorage gefunden, validiere...');
          
          final isValid = JwtHelper.decodeToken(_authService.jwt!) != null;
          final isExpired = isValid ? JwtHelper.isTokenExpired(_authService.jwt!) : true;
          
          if (!isValid || isExpired) {
            print('❌ JWT in SecureStorage ist ungültig - cleane alles');
            
            final storage = const FlutterSecureStorage();
            await storage.deleteAll();
            await _authService.signOut();
            
            print('✅ SecureStorage geleert - bereit für Neu-Login');
          }
        }
      }
    } catch (e) {
      print('❌ Fehler beim Initialisieren des Web-Login: $e');
      
      // Bei Fehler: ALLE Storages manuell cleanen
      html.removeFromLocalStorage('neon_jwt');
      html.removeFromLocalStorage('neon_user_email');
      html.removeFromLocalStorage('neon_session_id');
      
      final storage = const FlutterSecureStorage();
      await storage.deleteAll();
      
      await _authService.signOut();
      
      print('✅ Alle Storages nach Fehler geleert');
    }
  }
  
  Future<void> _checkOAuthCallback() async {
    if (platform.isAndroid()) {
      try {
        const platform = MethodChannel('com.sws.dietry/deeplink');
        final String? initialLink = await platform.invokeMethod('getInitialLink');
        
        if (initialLink == null || initialLink.isEmpty) {
          return;
        }
        
        final uri = Uri.parse(initialLink);
        
        // Prüfe ob es ein OAuth Callback ist
        final _androidCbUri = Uri.tryParse(AppConfig.androidCallbackUrl);
        if (_androidCbUri != null &&
            uri.scheme == _androidCbUri.scheme &&
            uri.host == _androidCbUri.host &&
            uri.path == _androidCbUri.path) {
          final verifier = uri.queryParameters['neon_auth_session_verifier'];
          
          if (verifier != null && verifier.isNotEmpty) {
            // ✅ Nutze NeonAuthService für Session-Exchange
            final success = await _authService.getSessionWithVerifier(verifier);
            
            if (success && _authService.jwt != null) {
              // Setze JWT im Database Service
              await _dbService?.setJWT(_authService.jwt!);
              
              print('✅ Android Login erfolgreich: ${_authService.session?['user']?['email']}');
            } else {
              print('❌ Session-Exchange fehlgeschlagen');
            }
          }
        }
      } catch (e) {
        print('❌ Fehler beim Android Deep Link Handling: $e');
      }
    }
  }



  void _onAuthChanged() {
    final jwt = _authService.jwt;
    final db = _dbService;
    if (jwt != null && _authService.isLoggedIn && db != null) {
      // Sync new JWT to DB service (e.g. after auto-refresh).
      db.setJWT(jwt).catchError((e) {
        print('⚠️ Fehler beim Sync des JWT nach Auth-Änderung: $e');
      });
      // Aktualisiere Premium-Feature-Gates aus JWT-Claim.
      AppFeatures.setFromJwt(jwt);
    } else if (!_authService.isLoggedIn && db != null) {
      // Clear stale JWT from db service on sign-out.
      db.clearSession().catchError((e) {
        print('⚠️ Fehler beim Clearen der DB-Session: $e');
      });
      AppFeatures.reset();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final db = _dbService;
    if (_authService.isLoading || db == null) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (!_authService.isLoggedIn) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: LoginScreen(
          authService: _authService,
          dbService: db,
          onLocaleChanged: (locale) => setState(() => _locale = locale),
        ),
      );
    }
    return MaterialApp(
      title: 'Dietry',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      locale: _locale,
      home: DietryHomeWithLogout(
        key: ValueKey(_authService.session?['user']?['id'] ?? _authService.jwt),
        authService: _authService,
        dbService: db,
        onLocaleChanged: (locale) => setState(() => _locale = locale),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

// Wrapper für DietryHome mit Logout-Button
class DietryHomeWithLogout extends StatefulWidget {
  final NeonAuthService authService;
  final NeonDatabaseService dbService;
  final void Function(Locale?) onLocaleChanged;

  const DietryHomeWithLogout({
    super.key,
    required this.authService,
    required this.dbService,
    required this.onLocaleChanged,
  });

  @override
  State<DietryHomeWithLogout> createState() => _DietryHomeWithLogoutState();
}

class _DietryHomeWithLogoutState extends State<DietryHomeWithLogout> {
  final _dietryHomeKey = GlobalKey<_DietryHomeState>();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: DietryHome(
        key: _dietryHomeKey,
        dbService: widget.dbService,
        authService: widget.authService,
      ),
      appBar: AppBar(
        title: Text(l.appBarTitle),
        bottom: AppConfig.isDevelopment
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Container(
                  width: double.infinity,
                  color: Colors.orange.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    l.devBannerText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          // Sprache wechseln
          PopupMenuButton<Locale?>(
            icon: const Icon(Icons.language),
            tooltip: l.languageTooltip,
            onSelected: widget.onLocaleChanged,
            itemBuilder: (_) => [
              const PopupMenuItem(value: Locale('de'), child: Text('🇩🇪  Deutsch')),
              const PopupMenuItem(value: Locale('en'), child: Text('🇬🇧  English')),
              const PopupMenuItem(value: Locale('es'), child: Text('🇪🇸  Español')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: null, child: Text('⚙️  System')),
            ],
          ),
          // Info / Impressum
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l.infoTooltip,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InfoScreen()),
              );
            },
          ),
          // Profil
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: l.profileTooltip,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(
                    dbService: widget.dbService,
                    authService: widget.authService,
                  ),
                ),
              );

              // Nach Rückkehr: Goal neu laden (Ziel könnte geändert worden sein)
              _dietryHomeKey.currentState?._loadCurrentGoal();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.logoutTooltip,
            onPressed: () async {
              await widget.authService.signOut();
            },
          ),
        ],
      ),
    );
  }
}

class DietryHome extends StatefulWidget {
  final NeonDatabaseService dbService;
  final NeonAuthService authService;
  
  const DietryHome({
    Key? key,
    required this.dbService,
    required this.authService,
  }) : super(key: key);

  @override
  State<DietryHome> createState() => _DietryHomeState();
}

class _DietryHomeState extends State<DietryHome> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  DateTime _selectedDay = DateTime.now();

  final _store = DataStore.instance;
  final _sync = SyncService.instance;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.init(widget.dbService);
    _store.addListener(_onStoreChanged);
    _sync.init(widget.dbService);
    _initializeAndLoadData();
    // Refresh data every 60 s while the app is in the foreground.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _silentRefresh());
    WaterReminderService.onInAppReminder = _showWaterReminder;
    WaterReminderService.getWaterStatus = () =>
        (_store.waterIntakeMl, _store.goal?.waterGoalMl ?? 2000);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _store.removeListener(_onStoreChanged);
    WaterReminderService.onInAppReminder = null;
    WaterReminderService.getWaterStatus = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _silentRefresh();
    }
  }

  /// Reload current day without showing a full-screen spinner.
  Future<void> _silentRefresh() async {
    if (widget.dbService.userId == null) return;
    await _store.loadDay(_selectedDay, silent: true, delta: true);
    _sync.processPendingQueue();
  }

  void _showWaterReminder(String title, String body) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Text('💧', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(body)),
          ],
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: '+250 ml', onPressed: () {
          // Immer zum heutigen Tag hinzufügen, unabhängig vom angezeigten Tag.
          _addWaterToday(250);
        }),
      ),
    );
  }

  /// Fügt [deltaMl] zum heutigen Wasserstand hinzu.
  /// Wird vom Reminder-Snackbar aufgerufen — immer für heute, egal welcher
  /// Tag gerade in der Navigation ausgewählt ist.
  Future<void> _addWaterToday(int deltaMl) async {
    final today = DateTime.now();
    if (DateUtils.isSameDay(_selectedDay, today)) {
      // Heute ist ausgewählt → normaler Pfad, aktualisiert auch die UI.
      await _onWaterChanged(deltaMl);
      return;
    }
    // Anderer Tag ausgewählt → heutigen Stand aus der DB holen und aktualisieren.
    final currentIntake = await WaterIntakeService(widget.dbService)
        .getIntakeForDate(today);
    final newAmount = (currentIntake + deltaMl).clamp(0, 9999);
    await WaterIntakeService(widget.dbService)
        .setIntakeForDate(today, newAmount);
  }

  void _onStoreChanged() {
    if (!mounted) return;
    // Drain milestone celebrations before rebuilding.
    final milestones = _store.pendingMilestones;
    if (milestones.isNotEmpty) {
      _store.clearPendingMilestones();
      // Show only the highest milestone in this batch to avoid stacking dialogs.
      final highest = milestones.reduce((a, b) => a > b ? a : b);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMilestoneCelebration(highest);
      });
    }
    setState(() {});
  }

  void _showMilestoneCelebration(int milestone) {
    final l = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.streakDays(milestone),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(l.streakMilestoneBody(milestone)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('🎉  OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeAndLoadData() async {
    await Future.delayed(const Duration(milliseconds: 100));
    int attempts = 0;
    while (widget.dbService.userId == null && attempts < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    if (widget.dbService.userId == null) {
      _store.setGoal(null); // triggers isInitialLoading = false via loadDay
      return;
    }
    await _store.loadDay(_selectedDay);
    // Try flushing any queued operations now that we're online.
    _sync.processPendingQueue();
  }

  Future<void> _loadCurrentGoal() async {
    await _store.loadDay(_selectedDay);
  }

  Future<void> _onWaterChanged(int deltaMl) async {
    final before = _store.waterIntakeMl;
    final newAmount = (before + deltaMl).clamp(0, 9999);
    _store.setWaterIntakeMl(newAmount); // optimistic
    final saved = await WaterIntakeService(widget.dbService)
        .setIntakeForDate(_selectedDay, newAmount);
    if (saved == null) {
      _store.setWaterIntakeMl(before); // revert to exact previous value
    }
  }

  Future<void> _jumpToToday() async {
    final today = DateTime.now();
    if (DateUtils.isSameDay(_selectedDay, today)) return;
    setState(() => _selectedDay = today);
    await _store.loadDay(today);
  }

  Future<void> _toggleCheatDay() async {
    final svc = CheatDayService(widget.dbService);
    final wasCheatDay = _store.isCheatDay;

    // Optimistic update
    _store.setCheatDay(!wasCheatDay);

    try {
      if (wasCheatDay) {
        await svc.unmarkCheatDay(_selectedDay);
      } else {
        await svc.markCheatDay(_selectedDay);
      }
      // Refresh streak after toggle (cloud: also persists record + queues milestones).
      await _store.checkAndUpdateStreak();

      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      if (!wasCheatDay) {
        // Show monthly nudge if > 2 cheat days this month
        final monthCount = await svc.countThisMonth(_selectedDay);
        if (!mounted) return;
        final message = monthCount > 2
            ? l.cheatDayMonthlyNudge(monthCount)
            : l.cheatDayMarked;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.cheatDayRemoved), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      // Revert optimistic update on error
      _store.setCheatDay(wasCheatDay);
    }
  }

  /// Wechselt den ausgewählten Tag und lädt das entsprechende Goal
  void _changeDay(int offset) async {
    final newDay = _selectedDay.add(Duration(days: offset));
    final today = DateTime.now();
    
    // ✅ Normalisiere beide Daten auf 00:00:00 für korrekten Vergleich
    final newDayNormalized = DateTime(newDay.year, newDay.month, newDay.day);
    final todayNormalized = DateTime(today.year, today.month, today.day);
    
    // ✅ Beschränkung 1: Nicht in die Zukunft blättern
    if (newDayNormalized.isAfter(todayNormalized)) {
      print('⚠️ Kann nicht in die Zukunft blättern (heute ist ${today.toIso8601String().split('T')[0]})');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.cannotNavigateToFuture),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // ✅ Beschränkung 2: Prüfe ob Goal für neuen Tag existiert (beim Zurückblättern)
    if (offset < 0) {
      final goalService = NutritionGoalService(widget.dbService);
      final hasGoal = await goalService.hasGoalForDate(newDay);
      
      if (!mounted) return;  // ✅ Prüfe nach async Operation
      
      if (!hasGoal) {
        print('⚠️ Kein Goal für ${newDay.toIso8601String().split('T')[0]} gefunden');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.noGoalForDate(
                DateFormat.yMd(Localizations.localeOf(context).toString()).format(newDay),
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }
    
    if (!mounted) return;

    setState(() => _selectedDay = newDay);
    await _store.loadDay(newDay);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_store.isInitialLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l.loading),
            ],
          ),
        ),
      );
    }

    if (_store.goal == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 24),
                Text(
                  l.noGoalTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l.noGoalMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () async {
                    // Navigiere zu Goal-Empfehlung
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GoalRecommendationScreen(
                          dbService: widget.dbService,
                        ),
                      ),
                    );

                    // Nach Rückkehr: Goal neu laden
                    _loadCurrentGoal();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(l.createGoal),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              OverviewScreen(
                goal: _store.goal!,
                entries: _store.foodEntries,
                activities: _store.activities,
                waterIntakeMl: _store.waterIntakeMl,
                selectedDay: _selectedDay,
                onChangeDay: _changeDay,
                onJumpToToday: _jumpToToday,
                onWaterChanged: _onWaterChanged,
                dbService: widget.dbService,
                isCheatDay: _store.isCheatDay,
                streak: _store.streak,
                bestStreak: _store.bestStreak,
                onToggleCheatDay: _toggleCheatDay,
              ),
              FoodEntriesListScreen(
                dbService: widget.dbService,
                selectedDay: _selectedDay,
                onChangeDay: _changeDay,
                onJumpToToday: _jumpToToday,
              ),
              ActivitiesListScreen(
                dbService: widget.dbService,
                selectedDay: _selectedDay,
                onChangeDay: _changeDay,
                onJumpToToday: _jumpToToday,
              ),
            ],
          ),
          if (_store.isLoading)
            Container(
              color: Colors.black26,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(l.loading),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Offline-Banner
          ListenableBuilder(
            listenable: _sync,
            builder: (context, _) {
              if (_sync.isOnline && _sync.pendingCount == 0) return const SizedBox.shrink();
              return Positioned(
                top: 0, left: 0, right: 0,
                child: Material(
                  color: _sync.isOnline ? Colors.orange.shade700 : Colors.red.shade700,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _sync.isOnline ? Icons.sync : Icons.wifi_off,
                          color: Colors.white, size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _sync.isOnline
                              ? '${_sync.pendingCount} ${l.pendingSyncCount}'
                              : l.offlineMode,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        if (_sync.isOnline && _sync.pendingCount > 0)
                          TextButton(
                            onPressed: _sync.processPendingQueue,
                            child: Text(l.syncNow,
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.assessment),
            label: l.navOverview,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.restaurant_menu),
            label: l.navEntries,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.directions_run),
            label: l.navActivities,
          ),
        ],
      ),
    );
  }

}

// Übersicht-Screen mit Nährwert-Tabelle, Kreisdiagramm und Tag-Wechsel
class OverviewScreen extends StatelessWidget {
  final NutritionGoal goal;
  final List<FoodEntry> entries;
  final List<PhysicalActivity> activities;
  final int waterIntakeMl;
  final DateTime selectedDay;
  final void Function(int offset) onChangeDay;
  final VoidCallback onJumpToToday;
  final void Function(int deltaMl) onWaterChanged;
  final NeonDatabaseService dbService;
  final bool isCheatDay;
  final int streak;
  final int bestStreak;
  final Future<void> Function() onToggleCheatDay;

  const OverviewScreen({
    super.key,
    required this.goal,
    required this.entries,
    required this.activities,
    required this.waterIntakeMl,
    required this.selectedDay,
    required this.onChangeDay,
    required this.onJumpToToday,
    required this.onWaterChanged,
    required this.dbService,
    required this.isCheatDay,
    required this.streak,
    required this.bestStreak,
    required this.onToggleCheatDay,
  });

  // Berechne Gesamt-Nährwerte aus entries
  double get totalCalories => entries.fold(0, (sum, e) => sum + e.calories);
  double get totalProtein => entries.fold(0, (sum, e) => sum + e.protein);
  double get totalFat => entries.fold(0, (sum, e) => sum + e.fat);
  double get totalCarbs => entries.fold(0, (sum, e) => sum + e.carbs);

  // ✅ Berechne verbrannte Kalorien aus activities
  double get totalCaloriesBurned => activities.fold(0.0, (sum, a) => sum + (a.caloriesBurned ?? 0));

  Widget _buildWaterCard(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final waterGoal = goal.waterGoalMl ?? 2000;
    final progress = (waterIntakeMl / waterGoal).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop, color: Colors.blue),
                const SizedBox(width: 8),
                Text(l.waterTitle, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.blue.shade100,
              color: Colors.blue,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$waterIntakeMl ml', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(l.waterGoalLabel(waterGoal)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  icon: const Icon(Icons.remove),
                  style: IconButton.styleFrom(backgroundColor: Colors.blue.shade100, foregroundColor: Colors.blue),
                  onPressed: waterIntakeMl >= 250 ? () => onWaterChanged(-250) : null,
                  tooltip: l.waterRemove,
                ),
                const SizedBox(width: 24),
                Text(
                  '+250 ml',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(width: 24),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  onPressed: () => onWaterChanged(250),
                  tooltip: l.waterAdd,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    // Lokalisierte Datumsanzeige
    String formattedDate = DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(selectedDay);
    final isToday = DateUtils.isSameDay(selectedDay, DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: l.previousDay,
                onPressed: () => onChangeDay(-1),
              ),
              Column(
                children: [
                  Text(
                    l.overviewTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    formattedDate,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (!isToday)
                    TextButton(
                      onPressed: onJumpToToday,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(l.today,
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: l.nextDay,
                onPressed: () => onChangeDay(1),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Streak + Cheat Day row ──────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Streak chip — cloud only
              if (AppFeatures.streaks) ...[
                Tooltip(
                  message: bestStreak > 0 ? l.streakBestLabel(bestStreak) : '',
                  child: Chip(
                    avatar: Text(
                      streak >= 7 ? '🔥' : (streak > 0 ? '✨' : '💤'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    label: Text(
                      streak > 0 ? l.streakDays(streak) : l.streakStart,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: streak >= 7
                        ? Colors.orange.shade50
                        : streak > 0
                            ? Colors.amber.shade50
                            : Colors.grey.shade100,
                    side: BorderSide(
                      color: streak >= 7
                          ? Colors.orange.shade300
                          : streak > 0
                              ? Colors.amber.shade300
                              : Colors.grey.shade300,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // Cheat Day toggle chip
              FilterChip(
                avatar: Text(
                  isCheatDay ? '🎉' : '🍕',
                  style: const TextStyle(fontSize: 14),
                ),
                label: Text(
                  l.markAsCheatDay,
                  style: const TextStyle(fontSize: 12),
                ),
                selected: isCheatDay,
                onSelected: (_) => onToggleCheatDay(),
                selectedColor: Colors.orange.shade100,
                checkmarkColor: Colors.orange.shade800,
                side: BorderSide(
                  color: isCheatDay ? Colors.orange.shade400 : Colors.grey.shade300,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),

          // ── Cheat Day banner ────────────────────────────────────────────
          if (isCheatDay) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.orange.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.orange.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.cheatDayBanner,
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          // Kalorien-Fortschritt (mit verbrannten Kalorien)
          Text(l.nutrientCalories),
          LinearProgressIndicator(
            value: goal.calories > 0 ? (totalCalories / goal.calories).clamp(0, 1) : 0,
            minHeight: 12,
            backgroundColor: Colors.grey[300],
            color: Colors.deepPurple,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${l.consumed}: ${totalCalories.toStringAsFixed(0)} kcal'),
              if (totalCaloriesBurned > 0)
                Text(
                  '${l.caloriesBurned}: ${totalCaloriesBurned.toStringAsFixed(0)} kcal',
                  style: TextStyle(color: Colors.green.shade700),
                ),
              Text('${l.goal}: ${goal.calories.toStringAsFixed(0)} kcal'),
            ],
          ),
          Text(
            '${l.remaining}: ${((goal.calories - totalCalories + totalCaloriesBurned).clamp(0, goal.calories * 2)).toStringAsFixed(0)} kcal',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: (goal.calories - totalCalories + totalCaloriesBurned) >= 0
                  ? Colors.green
                  : Colors.red,
            ),
          ),
          const SizedBox(height: 24),
          // Makronährstoff-Kreisdiagramm
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: totalProtein,
                    color: Colors.blue,
                    title: l.nutrientProtein,
                  ),
                  PieChartSectionData(
                    value: totalFat,
                    color: Colors.orange,
                    title: l.nutrientFat,
                  ),
                  PieChartSectionData(
                    value: totalCarbs,
                    color: Colors.green,
                    title: l.nutrientCarbs,
                  ),
                ],
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Wasser-Tracking
          _buildWaterCard(context),
          const SizedBox(height: 24),
          // Nährwert-Tabelle mit verbrannten Kalorien
          DataTable(
            columns: [
              const DataColumn(label: Text('')),
              DataColumn(label: Text(l.goal)),
              DataColumn(label: Text(l.consumed)),
              DataColumn(label: Text(l.caloriesBurned)),  // ✅ Neue Spalte
              DataColumn(label: Text(l.remaining)),
            ],
            rows: [
              DataRow(cells: [
                DataCell(Text(l.nutrientCalories)),
                DataCell(Text(goal.calories.toStringAsFixed(0))),
                DataCell(Text(totalCalories.toStringAsFixed(0))),
                DataCell(Text(
                  totalCaloriesBurned.toStringAsFixed(0),
                  style: TextStyle(color: Colors.green.shade700),
                )),
                DataCell(Text(
                  ((goal.calories - totalCalories + totalCaloriesBurned).clamp(0, goal.calories * 2)).toStringAsFixed(0),
                  style: TextStyle(
                    color: (goal.calories - totalCalories + totalCaloriesBurned) >= 0
                        ? Colors.green
                        : Colors.red,
                  ),
                )),
              ]),
              DataRow(cells: [
                DataCell(Text(l.nutrientProtein)),
                DataCell(Text(goal.protein.toStringAsFixed(1))),
                DataCell(Text(totalProtein.toStringAsFixed(1))),
                const DataCell(Text('-')),  // Keine verbrannten Makros
                DataCell(Text((goal.protein - totalProtein).clamp(0, goal.protein).toStringAsFixed(1))),
              ]),
              DataRow(cells: [
                DataCell(Text(l.nutrientFat)),
                DataCell(Text(goal.fat.toStringAsFixed(1))),
                DataCell(Text(totalFat.toStringAsFixed(1))),
                const DataCell(Text('-')),  // Keine verbrannten Makros
                DataCell(Text((goal.fat - totalFat).clamp(0, goal.fat).toStringAsFixed(1))),
              ]),
              DataRow(cells: [
                DataCell(Text(l.nutrientCarbs)),
                DataCell(Text(goal.carbs.toStringAsFixed(1))),
                DataCell(Text(totalCarbs.toStringAsFixed(1))),
                const DataCell(Text('-')),  // Keine verbrannten Makros
                DataCell(Text((goal.carbs - totalCarbs).clamp(0, goal.carbs).toStringAsFixed(1))),
              ]),
            ],
          ),
          // Mikronährstoff-Karte (Premium, konfigurierbar)
          if (AppFeatures.microNutrients) ...[
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final jwt = dbService.jwt;
              final userId = dbService.userId;
              if (jwt == null || userId == null) return const SizedBox.shrink();
              return premiumFeatures.buildMicroOverviewCard(
                entryIds: entries.map((e) => e.id).toList(),
                userId: userId,
                authToken: jwt,
                apiUrl: NeonDatabaseService.dataApiUrl,
              );
            }),
          ],
        ],
      ),
    );
  }
}

// Eintragen-Screen (Platzhalter)
class AddFoodScreen extends StatelessWidget {
  final void Function(FoodEntry) onAdd;
  final DateTime selectedDay;
  final void Function(int offset) onChangeDay;
  final List<FoodEntry> entries;

  const AddFoodScreen({
    super.key,
    required this.onAdd,
    required this.selectedDay,
    required this.onChangeDay,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    String formattedDate = DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(selectedDay);
    // Gruppiere Einträge nach MealType
    final Map<MealType, List<FoodEntry>> grouped = {
      for (var type in MealType.values) type: []
    };
    for (var entry in entries) {
      grouped[entry.mealType]?.add(entry);
    }
    return Column(
      children: [
        // Tag-Anzeige mit Vor-/Zurück-Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: l.previousDay,
              onPressed: () => onChangeDay(-1),
            ),
            Column(
              children: [
                Text(
                  l.addFoodTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  formattedDate,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: l.nextDay,
              onPressed: () => onChangeDay(1),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            children: [
              for (var type in MealType.values)
                if (grouped[type]!.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Text(
                          type.localizedName(l),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ...grouped[type]!.map((entry) => Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              title: Text(entry.name),
                              subtitle: Text(
                                '${entry.unit == 'g' || entry.unit == 'ml' ? '${entry.amount.toStringAsFixed(0)}${entry.unit}' : '${entry.amount == entry.amount.truncateToDouble() ? entry.amount.toInt() : entry.amount.toStringAsFixed(1)} × ${entry.unit}'} | '
                                'Kcal: ${entry.calories.toStringAsFixed(0)}',
                              ),
                            ),
                          )),
                    ],
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
