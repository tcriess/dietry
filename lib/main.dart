import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show MethodChannel, TextInput;
import 'package:shared_preferences/shared_preferences.dart';
import 'main_web_imports_web.dart' if (dart.library.io) 'main_web_imports.dart' as html;
import 'dart:async';
import 'dart:math' show min;
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
import 'services/food_entry_service.dart';
import 'services/physical_activity_service.dart';
import 'services/jwt_helper.dart';
import 'services/data_store.dart';
import 'services/sync_service.dart';
import 'services/water_intake_service.dart';
import 'services/water_reminder_service.dart';
import 'services/cheat_day_service.dart';
import 'services/guest_mode_service.dart';
import 'services/guest_migration_service.dart';
import 'services/user_body_measurements_service.dart';
import 'services/local_data_service.dart';
import 'app_config.dart';
import 'services/server_config_service.dart';
import 'services/feedback_service.dart';
import 'services/app_logger.dart';
import 'widgets/feedback_dialog.dart';

// Models
import 'models/models.dart';

// Screens
import 'screens/goal_recommendation_screen.dart';
import 'screens/food_entries_list_screen.dart';
import 'screens/add_food_entry_screen.dart';
import 'widgets/quick_food_entry_sheet.dart';
import 'screens/activities_list_screen.dart';
import 'screens/add_activity_screen.dart';
import 'screens/activity_database_screen.dart';
import 'screens/food_database_screen.dart';
import 'screens/profile_screen.dart';
import 'services/health_connect_service.dart';
import 'screens/info_screen.dart';
import 'screens/reports_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize app logger with configured log level
  initializeAppLogger();

  // Initialize guest mode flag from SharedPreferences
  await GuestModeService.init();

  // Initialize AppFeatures from environment (for PREMIUM_ROLE override in dev/test)
  AppFeatures.initializeFromEnvironment();

  // Platform-specific database initialization
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS)) {
    // Desktop: Use FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appLogger.d('🖥️ Desktop platform: Using SQLite FFI');
  }
  // Web: LocalDataService will use idb_shim's IndexedDB API directly
  // Mobile (Android/iOS): Uses default sqflite (no setup needed)

  // Load any user-configured server URLs before services start.
  try {
    await ServerConfigService.loadIntoCache();
  } catch (e) {
    appLogger.d('⚠️ ServerConfigService init failed: $e');
  }

  // Web: Auth-Base-URL in localStorage schreiben, damit auth_callback.html
  // dieselbe URL verwendet wie die Flutter-App (verhindert Cookie-Domain-Mismatch).
  if (kIsWeb) {
    html.setToLocalStorage(
      'dietry_auth_base_url', ServerConfigService.effectiveAuthBaseUrl);
  }

  try {
    await WaterReminderService.initialize();
  } catch (e) {
    appLogger.d('⚠️ WaterReminderService init failed: $e');
  }

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
            if (AppConfig.showDeveloperBanner)
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
            if (GuestModeService.isGuestMode)
              Container(
                width: double.infinity,
                color: Colors.blue.shade600,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: Text(
                  l.guestModeBannerText,
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
                final messenger = ScaffoldMessenger.of(context);
                final lErr = AppLocalizations.of(context)!;
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

                    FutureOr<shelf.Response> handler(shelf.Request request) async {
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
                    }

                    // Port 0 → OS assigns a free port; read it back via server.port.
                    final server = await shelf_io.serve(handler, 'localhost', 0);
                    callbackUrl = 'http://localhost:${server.port}/callback';
                    desktopCallbackCompleter.future.timeout(
                      const Duration(minutes: 5),
                      onTimeout: () => '',
                    ).whenComplete(() => server.close());
                  } else {
                    // iOS/macOS: Use HTTPS callback like Android (WebView will intercept)
                    callbackUrl = AppConfig.androidCallbackUrl;
                  }
                  
                  // ✅ Starte OAuth-Flow via NeonAuthService
                  final redirectUrl = await authService.startOAuthFlow(
                    provider: 'google',
                    callbackUrl: callbackUrl,
                  );
                  
                  appLogger.d('🔗 OAuth URL: $redirectUrl');
                  

                  // Öffne OAuth-URL (plattformabhängig)
                  if (platform.isAndroid()) {
                    // Android: Chrome Custom Tab (CCT) öffnen, Callback via App Link
                    // CCT schließt sich automatisch wenn das App Link Intent feuert
                    // und die Activity resumes — kein Browser-Tab bleibt offen
                    // (Challenge-Cookie wird von NeonAuthService verwaltet)

                    if (!await launchUrl(Uri.parse(redirectUrl), mode: LaunchMode.inAppBrowserView)) {
                      throw Exception('Konnte Browser nicht öffnen');
                    }
                    
                    if (context.mounted) {
                      messenger.showSnackBar(
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
                      messenger.showSnackBar(
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
                        if (context.mounted) {
                          // Setze JWT im GLOBALEN Database Service
                          // Zugriff via findAncestorStateOfType
                          final authAppState = context.findAncestorStateOfType<_AuthAppState>();
                          if (authAppState != null) {
                            await authAppState._dbService?.setJWT(authService.jwt!);
                          }

                          messenger.showSnackBar(
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
                      // ignore: use_build_context_synchronously
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
                          if (context.mounted) {
                            // Setze JWT im GLOBALEN Database Service
                            final authAppState = context.findAncestorStateOfType<_AuthAppState>();
                            if (authAppState != null) {
                              await authAppState._dbService?.setJWT(authService.jwt!);
                            }

                            messenger.showSnackBar(
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
                  appLogger.e('❌ Login fehlgeschlagen: $e');
                  if (context.mounted) {
                    messenger.showSnackBar(
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

            const SizedBox(height: 24),

            // Guest mode button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.person_outline),
                label: Text(l.continueAsGuest),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: () async {
                  try {
                    appLogger.d('[GuestButton] enable() starting...');
                    await GuestModeService.enable();
                    appLogger.d('[GuestButton] enable() completed, isGuestMode=${GuestModeService.isGuestMode}');

                    if (context.mounted) {
                      appLogger.d('[GuestButton] navigating to AuthApp with guest mode enabled...');
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AuthApp()),
                        (route) => false,
                      );
                    }
                  } catch (e) {
                    appLogger.e('❌ Error enabling guest mode: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.guestModeError),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ),

            const SizedBox(height: 8),

            // Guest mode note
            Text(
              l.guestModeNote,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
  bool _dbInitialized = false;
  bool _guestModeInitStarted = false;

  @override
  void initState() {
    super.initState();

    // Registriere App Lifecycle Observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize auth service for all modes
    _authService = NeonAuthService();

    // Check guest mode first
    if (GuestModeService.isGuestMode) {
      appLogger.i('👤 Guest mode enabled, initializing local storage...');
      _initGuestModeAsync();
    } else {
      // Remote mode: normal auth flow
      _authService.addListener(_onAuthChanged);

      // Web: Prüfe localStorage auf JWT asynchron
      if (kIsWeb) {
        _checkWebJWT();
      }

      // Initialisiere Database Service mit Token-Refresh-Callback.
      _initDatabaseService().catchError((e) {
        appLogger.e('Fehler bei DB-Initialisierung: $e');
        appLogger.d('[_initDatabaseService] ❌ EXCEPTION caught: $e');
        if (!_dbInitialized) {
          _dbInitialized = true;
          if (mounted) setState(() {});
        }
      });
    }
  }

  /// Async wrapper to initialize guest mode and trigger rebuild
  void _initGuestModeAsync() {
    appLogger.d('[_initGuestModeAsync] starting...');
    _initGuestMode().then((_) {
      appLogger.d('[_initGuestModeAsync] ✅ _initGuestMode completed');
      _dbInitialized = true;
      appLogger.d('[_initGuestModeAsync] set _dbInitialized=true, calling setState()');
      if (mounted) setState(() {});
    }).catchError((e) {
      appLogger.e('[_initGuestModeAsync] ❌ Error: $e');
      _dbInitialized = true;
      if (mounted) setState(() {});
    });
  }

  /// Initialize guest mode with local SQLite storage
  Future<void> _initGuestMode() async {
    appLogger.d('[_initGuestMode] Starting initialization');
    try {
      // Initialize local database
      appLogger.d('[_initGuestMode] Initializing LocalDataService...');
      final local = LocalDataService.instance;
      await local.init();
      appLogger.d('[_initGuestMode] LocalDataService initialized');

      // Initialize DataStore with local database
      appLogger.d('[_initGuestMode] Initializing DataStore with local...');
      DataStore.instance.initLocal(local);
      appLogger.d('[_initGuestMode] DataStore initialized');

      // Initialize SyncService with local database
      appLogger.d('[_initGuestMode] Initializing SyncService with local...');
      SyncService.instance.initLocal(local);
      appLogger.d('[_initGuestMode] SyncService initialized');

      appLogger.i('✅ Guest mode initialized successfully');
    } catch (e) {
      appLogger.e('❌ Error in _initGuestMode: $e');
      rethrow;
    }
  }
  
  Future<void> _initDatabaseService() async {
    final db = NeonDatabaseService();
    _dbService = db;

    // ✅ WICHTIG: Setze Token-Refresh-Callback VOR init()
    // Kein signOut() hier: dieser Callback wird auch während db.init() aufgerufen
    // (wenn ein abgelaufener Token aus dem Storage geladen wird). signOut() macht
    // einen Netzwerkaufruf ohne Timeout und würde db.init() zum Hängen bringen.
    db.onTokenExpired = () async {
      appLogger.i('🔄 Token-Refresh-Callback aufgerufen...');
      final success = await _authService.refreshToken();
      if (success) {
        appLogger.i('✅ Token erfolgreich refreshed via NeonAuthService');
        return _authService.jwt;
      } else {
        appLogger.w('⚠️ Token-Refresh fehlgeschlagen — returning null (no sign-out here)');
        return null;
      }
    };

    appLogger.d('[_initDatabaseService] Calling db.init()...');
    await db.init();
    appLogger.d('[_initDatabaseService] ✓ db.init() completed');

    // Wait for auth service to finish loading (includes expired-token refresh on startup).
    // Must complete before syncing JWT, otherwise we'd sync an expired token or null.
    appLogger.d('[_initDatabaseService] Waiting for auth service...');
    int waitMs = 0;
    const int maxWaitMs = 15000;
    while (_authService.isLoading && waitMs < maxWaitMs) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitMs += 100;
    }

    if (_authService.isLoading) {
      appLogger.d('[_initDatabaseService] ⚠️ Auth service still loading after timeout — proceeding without JWT');
    } else {
      appLogger.d('[_initDatabaseService] ✓ Auth service ready');
    }

    // Sync JWT to DB service (sets db.userId, enabling data queries).
    if (_authService.jwt != null) {
      try {
        appLogger.i('🔑 Setze JWT im DB-Service nach Auth-Init: ${_authService.jwt!.substring(0, 20)}...');
        await db.setJWT(_authService.jwt!);
        appLogger.d('[_initDatabaseService] ✓ JWT synced to DB service');
      } catch (e) {
        appLogger.w('⚠️ Fehler beim Setzen des JWT: $e');
      }
    } else {
      appLogger.i('ℹ️ Kein JWT im AuthService - User ist nicht eingeloggt');
    }

    // Only mark DB as initialized after JWT is synced. Setting this flag earlier
    // (before the auth wait + JWT sync) caused a startup race condition: DietryHome
    // mounted before db.userId was set, _initializeAndLoadData() timed out, and the
    // overview showed "no nutrition goal" until the user navigated away and back.
    _dbInitialized = true;
    appLogger.d('[_initDatabaseService] ✓ _dbInitialized = true');

    // Rebuild so the spinner is replaced by the home screen now that DB + JWT are ready.
    if (mounted) {
      setState(() {});
      appLogger.d('[_initDatabaseService] ✓ setState called');
    }

    // Fetch role here too: _onAuthChanged fires before _dbInitialized is true on
    // startup, so its role fetch is skipped. This ensures role is loaded on first login.
    final jwt = _authService.jwt;
    final userId = db.userId;
    if (jwt != null && _authService.isLoggedIn && userId != null) {
      appLogger.d('[_initDatabaseService] Fetching user role after DB init...');
      _fetchAndApplyRole(jwt: jwt, userId: userId);
    }

    appLogger.d('[_initDatabaseService] ✅ Database service initialization complete');
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

    if (state == AppLifecycleState.resumed) {
      // Android: Prüfe auf OAuth Callback wenn App in Vordergrund kommt
      // Dies wird NACH onNewIntent() aufgerufen, daher startString gesetzt ist
      if (platform.isAndroid() && !kIsWeb) {
        appLogger.d('📱 App resumed, checking OAuth callback...');
        _checkOAuthCallback();
      }

      // Aggressives Token-Refresh bei App-Resume
      // Wenn Token in weniger als 1 Stunde abläuft, refreshe es sofort
      _refreshTokenIfNeeded();
    }
  }

  /// Refresht Token wenn es in weniger als 1 Stunde abläuft
  /// Dies verbessert die Session-Persistenz nach längeren Pausen
  Future<void> _refreshTokenIfNeeded() async {
    if (!_authService.isLoggedIn || _authService.jwt == null) {
      return;
    }

    final timeLeft = _authService.timeUntilTokenExpiry;
    if (timeLeft == null) {
      return;
    }

    // Wenn Token in weniger als 1 Stunde abläuft, refresh es jetzt
    if (timeLeft.inMinutes < 60) {
      appLogger.d('⏰ Token expiring soon (${timeLeft.inMinutes} min) - refreshing on resume...');
      final success = await _authService.refreshTokenWithRetry(maxAttempts: 2);
      if (success) {
        appLogger.d('✅ Token refreshed on resume');
      } else {
        appLogger.d('⚠️ Token refresh on resume failed - will require re-login if session expired');
      }
    }
  }
  
  Future<void> _checkWebJWT() async {
    try {
      // ✅ WICHTIG: Warte bis AuthService fertig geladen hat
      // AuthService lädt JWT aus SecureStorage im Konstruktor
      while (_authService.isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      appLogger.d('🔍 AuthService initialisiert, prüfe Web-JWT...');
      
      final jwtFromStorage = html.getFromLocalStorage('neon_jwt');
      
      if (jwtFromStorage != null && jwtFromStorage.isNotEmpty) {
        appLogger.d('🔍 JWT in localStorage gefunden, validiere...');
        
        // Prüfe ob JWT gültig ist BEVOR wir es verwenden
        final isValid = JwtHelper.decodeToken(jwtFromStorage) != null;
        final isExpired = isValid ? JwtHelper.isTokenExpired(jwtFromStorage) : true;
        
        if (!isValid || isExpired) {
          appLogger.e('❌ JWT in localStorage ist ungültig oder abgelaufen');
          appLogger.i('   Cleane localStorage UND FlutterSecureStorage...');
          
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
          
          appLogger.i('✅ Alle Storages geleert - bereit für Neu-Login');
          return;
        }
        
        appLogger.i('✅ JWT ist gültig, setze in AuthService UND DB-Service...');
        
        // ✅ WICHTIG: Setze JWT im AuthService (für isLoggedIn)
        await _authService.setJWT(jwtFromStorage);
        
        // ✅ Setze auch im DB-Service (für Datenbank-Zugriff)
        await _dbService?.setJWT(jwtFromStorage);

        appLogger.i('✅ JWT in beiden Services gesetzt - User sollte eingeloggt sein');
      } else {
        appLogger.i('ℹ️ Kein JWT in localStorage - prüfe SecureStorage...');
        
        // Falls AuthService ein JWT aus SecureStorage geladen hat, validiere es
        if (_authService.jwt != null) {
          appLogger.d('🔍 JWT in SecureStorage gefunden, validiere...');
          
          final isValid = JwtHelper.decodeToken(_authService.jwt!) != null;
          final isExpired = isValid ? JwtHelper.isTokenExpired(_authService.jwt!) : true;
          
          if (!isValid || isExpired) {
            appLogger.e('❌ JWT in SecureStorage ist ungültig - cleane nur Auth-Keys');

            final storage = const FlutterSecureStorage();
            // ✅ WICHTIG: Nur Auth-Keys löschen, nicht deleteAll() verwenden!
            // deleteAll() würde auch Nutzer-Einstellungen wie water_reminder_enabled löschen
            await storage.delete(key: 'neon_jwt');
            await storage.delete(key: 'neon_session');
            await storage.delete(key: 'neon_cookie');
            await storage.delete(key: 'neon_challenge_cookie');

            await _authService.signOut();

            appLogger.i('✅ Auth-Keys gelöscht - Einstellungen bleiben erhalten');
          }
        }
      }
    } catch (e) {
      appLogger.e('❌ Fehler beim Initialisieren des Web-Login: $e');

      // Bei Fehler: Nur Auth-Daten cleanen (NICHT alle Einstellungen!)
      html.removeFromLocalStorage('neon_jwt');
      html.removeFromLocalStorage('neon_user_email');
      html.removeFromLocalStorage('neon_session_id');

      final storage = const FlutterSecureStorage();
      // ✅ Nur Auth-Keys löschen, nicht deleteAll()!
      await storage.delete(key: 'neon_jwt');
      await storage.delete(key: 'neon_session');
      await storage.delete(key: 'neon_cookie');
      await storage.delete(key: 'neon_challenge_cookie');

      await _authService.signOut();

      appLogger.i('✅ Auth-Daten nach Fehler gelöscht - Einstellungen bleiben erhalten');
    }
  }
  
  Future<void> _checkOAuthCallback() async {
    appLogger.d('🔍 _checkOAuthCallback called');
    if (platform.isAndroid()) {
      appLogger.d('📱 isAndroid=true, calling getInitialLink...');
      try {
        const platform = MethodChannel('com.sws.dietry/deeplink');
        final String? initialLink = await platform.invokeMethod('getInitialLink');
        appLogger.d('📞 getInitialLink returned: $initialLink');

        if (initialLink == null || initialLink.isEmpty) {
          appLogger.d('⚠️ initialLink is empty, returning');
          return;
        }

        appLogger.d('✓ initialLink is not empty');
        final uri = Uri.parse(initialLink);
        appLogger.d('✓ Parsed URI: ${uri.host}${uri.path}');

        // Prüfe ob es ein OAuth Callback ist
        final androidCbUri = Uri.tryParse(AppConfig.androidCallbackUrl);
        appLogger.d('✓ Expected callback URL: ${AppConfig.androidCallbackUrl}');

        if (androidCbUri != null &&
            uri.scheme == androidCbUri.scheme &&
            uri.host == androidCbUri.host &&
            uri.path == androidCbUri.path) {
          appLogger.d('✓ URL matches callback pattern');
          final verifier = uri.queryParameters['neon_auth_session_verifier'];
          appLogger.d('✓ Verifier: $verifier');

          if (verifier != null && verifier.isNotEmpty) {
            // ✅ Nutze NeonAuthService für Session-Exchange (braucht DB nicht)
            appLogger.d('🔐 OAuth Verifier empfangen, tausche gegen Session...');
            appLogger.d('⏳ Waiting for getSessionWithVerifier...');
            try {
              final success = await _authService.getSessionWithVerifier(verifier);
              appLogger.d('✓ getSessionWithVerifier returned: success=$success');

              if (success && _authService.jwt != null) {
                appLogger.d('✓ JWT is set: ${_authService.jwt!.substring(0, 20)}...');
                appLogger.d('✅ Android Login erfolgreich: ${_authService.session?['user']?['email']}');
                // JWT wird automatisch vom _onAuthChanged Listener in DB Service übernommen
              } else {
                appLogger.d('❌ Session-Exchange fehlgeschlagen: success=$success, jwt=${_authService.jwt != null}');
              }
            } catch (e) {
              appLogger.d('❌ Exception in getSessionWithVerifier: $e');
            }
          } else {
            appLogger.d('❌ Verifier is null or empty');
          }
        } else {
          appLogger.d('❌ URL does not match callback pattern');
          appLogger.d('   Expected: ${androidCbUri?.scheme}://${androidCbUri?.host}${androidCbUri?.path}');
          appLogger.d('   Got:      ${uri.scheme}://${uri.host}${uri.path}');
        }
      } catch (e) {
        appLogger.d('❌ Fehler beim Android Deep Link Handling: $e');
      }
    } else {
      appLogger.d('❌ isAndroid=false');
    }
  }



  void _onAuthChanged() {
    appLogger.d('🔄 [_onAuthChanged] Listener fired');
    appLogger.d('🔄 [_onAuthChanged] State: jwt=${_authService.jwt != null ? "SET (${_authService.jwt!.length} bytes)" : "NULL"}, isLoggedIn=${_authService.isLoggedIn}, db=${_dbService != null ? "SET" : "NULL"}, dbInit=$_dbInitialized');
    final jwt = _authService.jwt;
    final db = _dbService;

    if (jwt != null && _authService.isLoggedIn && db != null && _dbInitialized) {
      appLogger.d('[_onAuthChanged] ✓ All conditions met, syncing JWT to DB...');
      appLogger.d('[_onAuthChanged] ✓ JWT: ${jwt.substring(0, min(30, jwt.length))}...');
      // Sync new JWT to DB service (e.g. after auto-refresh).
      // Only call if db.init() has completed (_dio is initialized)
      appLogger.d('[_onAuthChanged] Calling db.setJWT...');
      db.setJWT(jwt).catchError((e, stackTrace) {
        appLogger.d('[_onAuthChanged] ❌ Error in setJWT: $e');
        appLogger.d('[_onAuthChanged] ❌ Stack trace: $stackTrace');
        appLogger.w('⚠️ Fehler beim Sync des JWT nach Auth-Änderung: $e');
      }).then((_) async {
        appLogger.d('[_onAuthChanged] ✓ setJWT completed successfully');
        // Check if user was in guest mode and has data to migrate
        if (mounted && GuestModeService.wasGuestMode) {
          appLogger.i('👤 User was in guest mode, checking for data to migrate...');
          _showGuestMigrationDialog(db);
        }
        final userId = db.userId;
        if (mounted && userId != null) {
          _fetchAndApplyRole(jwt: jwt, userId: userId);
        }
      });
    } else if (!_authService.isLoggedIn && db != null) {
      appLogger.d('[_onAuthChanged] ✓ User logged out, clearing session');
      // Clear stale JWT from db service on sign-out.
      db.clearSession().catchError((e) {
        appLogger.d('[_onAuthChanged] ⚠️ Error clearing DB session: $e');
        appLogger.w('⚠️ Fehler beim Clearen der DB-Session: $e');
      }).then((_) {
        appLogger.d('[_onAuthChanged] ✓ DB session cleared');
      });
      try {
        AppFeatures.reset();
        appLogger.d('[_onAuthChanged] ✓ Feature gates reset');
      } catch (e) {
        appLogger.d('[_onAuthChanged] ⚠️ Error resetting feature gates: $e');
      }
    } else {
      appLogger.d('[_onAuthChanged] ⚠️ No action taken');
      appLogger.d('[_onAuthChanged] ⚠️ jwt=${jwt != null ? "SET (${jwt.length} bytes)" : "NULL"}');
      appLogger.d('[_onAuthChanged] ⚠️ loggedIn=${_authService.isLoggedIn}');
      appLogger.d('[_onAuthChanged] ⚠️ db=${db != null ? "SET" : "NULL"}');
      appLogger.d('[_onAuthChanged] ⚠️ dbInit=$_dbInitialized');
      if (jwt != null && db != null && !_dbInitialized) {
        appLogger.d('[_onAuthChanged] ℹ️ JWT is available but DB not yet initialized — will be synced when DB ready');
      }
    }
    appLogger.d('[_onAuthChanged] Calling setState...');
    setState(() {
      appLogger.d('[_onAuthChanged] ✓ Inside setState callback');
    });
    appLogger.d('[_onAuthChanged] ✓ setState completed');
  }

  /// Restore cached role immediately, then fetch fresh role from DB and update cache.
  /// Called both from _onAuthChanged (resume/token-refresh) and _initDatabaseService
  /// (initial login), because the auth listener fires before DB is ready on startup
  /// and the role fetch would otherwise be silently skipped.
  Future<void> _fetchAndApplyRole({required String jwt, required String userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role_$userId');
    if (cachedRole != null && mounted) {
      AppFeatures.setRole(cachedRole);
      setState(() {});
    }
    premiumFeatures.fetchUserRole(
      userId: userId,
      authToken: jwt,
      apiUrl: AppConfig.dataApiUrl,
    ).then((role) {
      prefs.setString('user_role_$userId', role);
      AppFeatures.setRole(role);
      if (mounted) setState(() {});
    }).catchError((e) {
      appLogger.w('⚠️ Rolle konnte nicht abgerufen werden: $e');
    });
  }

  /// Check if user has any existing data in remote database
  Future<bool> _userHasExistingData(NeonDatabaseService db) async {
    try {
      // Check if user has any nutrition goals
      final goalService = NutritionGoalService(db);
      final goal = await goalService.getCurrentGoal();
      if (goal != null) {
        appLogger.d('ℹ️ User has existing nutrition goal');
        return true;
      }

      // Check if user has any food entries
      final foodService = FoodEntryService(db);
      final today = DateTime.now();
      final entries = await foodService.getFoodEntriesForDate(today);
      if (entries.isNotEmpty) {
        appLogger.d('ℹ️ User has existing food entries');
        return true;
      }

      // Check if user has any activities
      final activityService = PhysicalActivityService(db);
      final activities = await activityService.getActivitiesForDate(today);
      if (activities.isNotEmpty) {
        appLogger.d('ℹ️ User has existing activities');
        return true;
      }

      appLogger.d('✅ User is fresh (no existing data)');
      return false;
    } catch (e) {
      appLogger.w('⚠️ Could not check user data: $e');
      // If we can't check, assume user is fresh (be lenient)
      return false;
    }
  }

  Future<void> _showGuestMigrationDialog(NeonDatabaseService db) async {
    final l = AppLocalizations.of(context);
    if (l == null || !mounted) return;

    final local = LocalDataService.instance;
    final userId = JwtHelper.extractUserId(_authService.jwt ?? '');

    if (userId == null || userId.isEmpty) {
      appLogger.e('❌ Could not extract userId from JWT');
      _showSnackBar(l.migrationError);
      return;
    }

    // Check if user already has data
    appLogger.d('🔍 Checking if user has existing data...');
    final hasExistingData = await _userHasExistingData(db);

    if (hasExistingData) {
      appLogger.w('⚠️ User already has data, skipping migration');
      _showSnackBar('⚠️ Migration not possible: Account already has data');
      // Guest data is preserved — user can log out and try a different account
      return;
    }

    if (!mounted) return;

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.migrationDialogTitle),
        content: Text(l.migrationDialogContent),
        actions: [
          TextButton(
            onPressed: () {
              appLogger.d('Migration: User selected DISCARD');
              Navigator.of(dialogContext).pop(false);
            },
            child: Text(l.migrationDiscard),
          ),
          TextButton(
            onPressed: () {
              appLogger.d('Migration: User selected TRANSFER');
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(l.migrationTransfer),
          ),
        ],
      ),
    ).then((shouldTransfer) async {
      if (!mounted) return;

      if (shouldTransfer == true) {
        appLogger.i('🔄 Starting guest data migration...');
        try {
          final result = await GuestMigrationService.migrate(local, db, userId);

          if (mounted) {
            if (result.success) {
              appLogger.i('✅ Migration completed successfully');
              final summary = result.summary.isNotEmpty ? result.summary : 'Daten';
              _showSnackBar('✅ $summary übertragen');
              // Only clear guest data after successful migration
              await local.clearAll();
              await GuestModeService.disable();
              appLogger.i('✅ Guest data cleared after successful migration');
            } else {
              appLogger.w('⚠️ Migration completed with errors: ${result.errors.join(', ')}');
              _showSnackBar(l.migrationError);
              // Do NOT clear guest data if migration had errors
              appLogger.w('⚠️ Guest data preserved due to migration errors');
            }
          }
        } catch (e) {
          appLogger.e('❌ Migration failed: $e');
          if (mounted) {
            _showSnackBar(l.migrationError);
          }
          // Do NOT clear guest data if migration failed
          appLogger.w('⚠️ Guest data preserved due to migration failure');
        }
      } else {
        // User selected DISCARD
        appLogger.d('🗑️ User discarding guest data');
        await local.clearAll();
        await GuestModeService.disable();
        appLogger.i('✅ Guest data cleared by user');
      }
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = _dbService;

    // Guest mode check first
    if (GuestModeService.isGuestMode) {
      if (!_dbInitialized) {
        return MaterialApp(
          localizationsDelegates: [
            ...AppLocalizations.localizationsDelegates,
            ...CloudLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: _locale,
          home: const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      // Guest mode ready: show home screen without auth
      return MaterialApp(
        title: 'Dietry',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        locale: _locale,
        home: DietryHomeWithLogout(
          key: const ValueKey('guest_mode'),
          authService: _authService,
          dbService: db,
          isGuestMode: true,
          onLocaleChanged: (locale) => setState(() => _locale = locale),
        ),
        localizationsDelegates: [
          ...AppLocalizations.localizationsDelegates,
          ...CloudLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      );
    }

    // Remote mode: existing logic
    // Show spinner until both auth and DB are fully ready.
    // When logged in, also wait for _dbInitialized so the main screen never
    // renders before db.setJWT() has been called (otherwise data loading stalls).
    // When not logged in, show the login screen immediately — no DB needed.
    // Check if still loading (remote mode) or waiting for guest mode initialization
    final isGuestMode = GuestModeService.isGuestMode;
    appLogger.d('[build] isGuestMode=$isGuestMode, _dbInitialized=$_dbInitialized, _guestModeInitStarted=$_guestModeInitStarted');

    // Initialize guest mode if just activated
    if (isGuestMode && !_guestModeInitStarted) {
      appLogger.d('🔄 Guest mode detected in build(), starting initialization...');
      _guestModeInitStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appLogger.d('[addPostFrameCallback] calling _initGuestModeAsync()');
        _initGuestModeAsync();
      });
    }

    final authServiceLoading = _authService.isLoading;
    final remoteNeedsDb = !isGuestMode && (db == null || (_authService.isLoggedIn && !_dbInitialized));
    final guestNeedsDb = isGuestMode && !_dbInitialized;
    final isWaitingForInit = authServiceLoading || remoteNeedsDb || guestNeedsDb;

    appLogger.d('[build] isWaitingForInit=$isWaitingForInit: '
        'authServiceLoading=$authServiceLoading, remoteNeedsDb=$remoteNeedsDb, guestNeedsDb=$guestNeedsDb');

    if (isWaitingForInit) {
      return MaterialApp(
        localizationsDelegates: [
          ...AppLocalizations.localizationsDelegates,
          ...CloudLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Guest mode: show main app
    if (isGuestMode) {
      return MaterialApp(
        title: 'Dietry',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        locale: _locale,
        home: DietryHomeWithLogout(
          key: const ValueKey('guest'),
          authService: _authService,
          dbService: null,
          isGuestMode: true,
          onLocaleChanged: (locale) => setState(() => _locale = locale),
        ),
        localizationsDelegates: [
          ...AppLocalizations.localizationsDelegates,
          ...CloudLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      );
    }

    final rawJwt = _authService.jwt;
    if (rawJwt != null && JwtHelper.isTokenExpired(rawJwt)) {
      // Token expired and refresh failed — treat as logged out immediately.
      // Trigger background cleanup without waiting (signOut has no timeout).
      _authService.signOut().ignore();
      return MaterialApp(
        localizationsDelegates: [
          ...AppLocalizations.localizationsDelegates,
          ...CloudLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: LoginScreen(
          authService: _authService,
          dbService: db!,
          onLocaleChanged: (locale) => setState(() => _locale = locale),
        ),
      );
    }

    if (!_authService.isLoggedIn) {
      return MaterialApp(
        localizationsDelegates: [
          ...AppLocalizations.localizationsDelegates,
          ...CloudLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: LoginScreen(
          authService: _authService,
          dbService: db!,  // Non-null because isWaitingForInit checks db != null in remote mode
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
        isGuestMode: false,
        onLocaleChanged: (locale) => setState(() => _locale = locale),
      ),
      localizationsDelegates: [
        ...AppLocalizations.localizationsDelegates,
        ...CloudLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

// Wrapper für DietryHome mit Logout-Button
class DietryHomeWithLogout extends StatefulWidget {
  final NeonAuthService authService;
  final NeonDatabaseService? dbService;
  final void Function(Locale?) onLocaleChanged;
  final bool isGuestMode;

  const DietryHomeWithLogout({
    super.key,
    required this.authService,
    this.dbService,
    required this.onLocaleChanged,
    this.isGuestMode = false,
  });

  @override
  State<DietryHomeWithLogout> createState() => _DietryHomeWithLogoutState();
}

class _DietryHomeWithLogoutState extends State<DietryHomeWithLogout> {
  final _dietryHomeKey = GlobalKey<_DietryHomeState>();
  FeedbackService? _feedbackService;

  @override
  void initState() {
    super.initState();
    // Only initialize FeedbackService in remote mode
    if (!widget.isGuestMode && widget.dbService != null) {
      _feedbackService = FeedbackService(widget.dbService!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: DietryHome(
        key: _dietryHomeKey,
        dbService: widget.dbService,
        authService: widget.authService,
        isGuestMode: widget.isGuestMode,
      ),
      appBar: AppBar(
        title: Text(l.appBarTitle),
        bottom: (AppConfig.showDeveloperBanner || widget.isGuestMode)
            ? PreferredSize(
                preferredSize: Size.fromHeight(
                  (AppConfig.showDeveloperBanner ? 24 : 0) + (widget.isGuestMode ? 24 : 0),
                ),
                child: Column(
                  children: [
                    if (AppConfig.showDeveloperBanner)
                      Container(
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
                    if (widget.isGuestMode)
                      Container(
                        width: double.infinity,
                        color: Colors.blue.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          l.guestModeBannerText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : null,
        actions: [
          // Feedback (remote mode only)
          if (!widget.isGuestMode && _feedbackService != null)
            IconButton(
              icon: const Icon(Icons.feedback_outlined),
              tooltip: l.feedbackTooltip,
              onPressed: () => FeedbackDialog.show(context, _feedbackService!),
            ),
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
          // Profil / Ziel-Empfehlung
          if (widget.isGuestMode)
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: l.profileTooltip,
              onPressed: () async {
                // Guest mode: navigate to GoalRecommendationScreen for profile/goal setup
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GoalRecommendationScreen(
                      dbService: null,
                    ),
                  ),
                );
                _dietryHomeKey.currentState?._loadCurrentGoal();
              },
            )
          else if (widget.dbService != null)
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: l.profileTooltip,
              onPressed: () async {
                // Remote mode: navigate to ProfileScreen
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(
                      dbService: widget.dbService!,
                      authService: widget.authService,
                      isGuestMode: widget.isGuestMode,
                    ),
                  ),
                );

                // Nach Rückkehr: Goal neu laden (Ziel könnte geändert worden sein)
                _dietryHomeKey.currentState?._loadCurrentGoal();
              },
            ),
          // Delete guest data (guest mode only)
          if (widget.isGuestMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l.deleteGuestDataTitle,
              onPressed: () async {
                final l = AppLocalizations.of(context)!;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l.deleteGuestDataTitle),
                    content: Text(l.deleteGuestDataConfirm),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(l.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(l.delete),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  try {
                    await LocalDataService.instance.clearAll();
                    await GuestModeService.disable();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.deleteGuestDataSuccess),
                          backgroundColor: Colors.green,
                        ),
                      );
                      // Navigate to login screen
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AuthApp()),
                        (route) => false,
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.errorPrefix(e.toString())),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            ),
          // Sign in (guest mode) or Logout (remote mode)
          if (widget.isGuestMode)
            IconButton(
              icon: const Icon(Icons.login),
              tooltip: l.guestModeSignIn,
              onPressed: () async {
                await GuestModeService.disable();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthApp()),
                    (route) => false,
                  );
                }
              },
            )
          else
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
  final NeonDatabaseService? dbService;
  final NeonAuthService authService;
  final bool isGuestMode;

  const DietryHome({
    super.key,
    this.dbService,
    required this.authService,
    this.isGuestMode = false,
  });

  @override
  State<DietryHome> createState() => _DietryHomeState();
}

class _DietryHomeState extends State<DietryHome> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  DateTime _selectedDay = DateTime.now();
  final _reportsRefreshTrigger = ValueNotifier<int>(0);

  final _store = DataStore.instance;
  final _sync = SyncService.instance;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final db = widget.dbService;
    if (!widget.isGuestMode && db != null) {
      _store.init(db);
      _sync.init(db);
    }
    // Guest mode: services already initialized in _initGuestMode()

    _store.addListener(_onStoreChanged);
    _initializeAndLoadData();
    // Refresh data every 60 s while the app is in the foreground.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _silentRefresh());
    WaterReminderService.onInAppReminder = _showWaterReminder;
    WaterReminderService.getWaterStatus = () =>
        (_store.waterIntakeMl + _store.liquidFoodIntakeMl, _store.goal?.waterGoalMl ?? 2000);
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
    final db = widget.dbService;

    // Guest mode: no remote sync needed, just reload from local
    if (widget.isGuestMode || db == null) {
      await _store.loadDay(_selectedDay, silent: true);
      return;
    }

    // Remote mode: check userId and do delta sync
    if (db.userId == null) return;
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
        action: SnackBarAction(label: '+200 ml', onPressed: () {
          // Immer zum heutigen Tag hinzufügen, unabhängig vom angezeigten Tag.
          _addWaterToday(200);
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
    if (widget.dbService != null) {
      final currentIntake = await WaterIntakeService(widget.dbService!)
          .getIntakeForDate(today);
      final newAmount = (currentIntake + deltaMl).clamp(0, 9999);
      await WaterIntakeService(widget.dbService!)
          .setIntakeForDate(today, newAmount);
    }
  }

  Future<void> _showActivityQuickAdd() async {
    final db = widget.dbService;
    final jwt = db?.jwt;
    final userId = db?.userId;
    if (jwt == null || userId == null) return;
    premiumFeatures.showActivityQuickAddSheet(
      context: context,
      userId: userId,
      authToken: jwt,
      apiUrl: NeonDatabaseService.dataApiUrl,
      date: _selectedDay,
      onAdd: (data) async {
        final activity = PhysicalActivity(
          activityType: ActivityType.values.firstWhere(
            (t) => t.name == data.activityType,
            orElse: () => ActivityType.other,
          ),
          activityId: data.activityId,
          activityName: data.activityName,
          startTime: data.startTime,
          endTime: data.endTime,
          durationMinutes: data.durationMinutes,
          caloriesBurned: data.caloriesBurned,
          distanceKm: data.distanceKm,
          source: DataSource.manual,
        );
        final saved = await _sync.saveActivity(activity);
        _store.addActivity(saved ?? activity);
      },
    );
  }

  Future<void> _importFromHealthConnect(BuildContext ctx) async {
    final l = AppLocalizations.of(ctx)!;
    if (!HealthConnectService.isSupported) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l.healthConnectUnavailable)));
      return;
    }
    final hc = HealthConnectService();
    final granted = await hc.requestPermissions();
    if (!granted) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l.healthConnectUnavailable)));
      return;
    }
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l.healthConnectImporting)));
    try {
      final d = _selectedDay;
      final start = DateTime(d.year, d.month, d.day);
      final end = DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
      final imported = await hc.importActivities(start: start, end: end);
      if (imported.isEmpty) {
        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l.healthConnectNoResults)));
        return;
      }
      final db = widget.dbService;
      Set<String> existingHcIds = {};
      if (db != null) {
        final existing = await PhysicalActivityService(db).getActivitiesInRange(start: start, end: end);
        existingHcIds = existing.map((a) => a.healthConnectRecordId).whereType<String>().toSet();
      } else {
        existingHcIds = _store.activities.map((a) => a.healthConnectRecordId).whereType<String>().toSet();
      }
      final toSave = imported.where((a) => a.healthConnectRecordId == null || !existingHcIds.contains(a.healthConnectRecordId)).toList();
      for (final activity in toSave) {
        final saved = await _sync.saveActivity(activity);
        _store.addActivity(saved ?? activity);
      }
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(l.healthConnectSuccess(toSave.length)),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(l.healthConnectError(e.toString())),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _importBodyWeightsFromHealthConnect(BuildContext ctx) async {
    final l = AppLocalizations.of(ctx)!;
    final db = widget.dbService;
    if (db == null || !HealthConnectService.isSupported) return;

    final hc = HealthConnectService();
    final granted = await hc.requestPermissions();
    if (!granted) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l.healthConnectUnavailable)));
      return;
    }
    if (!ctx.mounted) return;

    final earliestGoalDate = await NutritionGoalService(db).getEarliestGoalDate();
    if (!ctx.mounted) return;

    final dateStr = earliestGoalDate != null
        ? '${earliestGoalDate.day.toString().padLeft(2, '0')}.${earliestGoalDate.month.toString().padLeft(2, '0')}.${earliestGoalDate.year}'
        : null;

    final useAllData = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) {
        final ld = AppLocalizations.of(dlgCtx)!;
        return SimpleDialog(
          title: Text(ld.importRangeTitle),
          children: [
            if (earliestGoalDate != null)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dlgCtx).pop(false),
                child: Text(ld.importRangeSinceGoal(dateStr!)),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(dlgCtx).pop(true),
              child: Text(ld.importRangeAll),
            ),
          ],
        );
      },
    );
    if (useAllData == null || !ctx.mounted) return;

    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l.healthConnectImporting)));

    try {
      final end = DateTime.now();
      final start = (useAllData || earliestGoalDate == null) ? DateTime(2000) : earliestGoalDate;
      final imported = await hc.importBodyMeasurements(start: start, end: end);

      if (imported.isEmpty) {
        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l.healthConnectNoResults)));
        return;
      }

      final service = UserBodyMeasurementsService(db);
      int saved = 0;
      for (final m in imported) {
        await service.saveMeasurement(m);
        saved++;
      }
      await NutritionGoalService.autoAdjustGoal(db);

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(l.healthConnectSuccessBody(saved)),
          backgroundColor: Colors.green,
        ));
        _reportsRefreshTrigger.value++;
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(l.healthConnectError(e.toString())),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  MealType _suggestMealType() {
    final hour = TimeOfDay.now().hour;
    if (hour < 10) return MealType.breakfast;
    if (hour < 14) return MealType.lunch;
    if (hour < 18) return MealType.snack;
    return MealType.dinner;
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

    // In guest mode, dbService is null; proceed directly to loading
    if (widget.isGuestMode || widget.dbService == null) {
      await _store.loadDay(_selectedDay);
      return;
    }

    int attempts = 0;
    while (widget.dbService!.userId == null && attempts < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    if (widget.dbService!.userId == null) {
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

    if (widget.dbService != null) {
      final saved = await WaterIntakeService(widget.dbService!)
          .setIntakeForDate(_selectedDay, newAmount);
      if (saved == null) {
        _store.setWaterIntakeMl(before); // revert to exact previous value
      }
    }
  }

  Future<void> _jumpToToday() async {
    final today = DateTime.now();
    if (DateUtils.isSameDay(_selectedDay, today)) return;
    setState(() => _selectedDay = today);
    await _store.loadDay(today);
  }

  Future<void> _toggleCheatDay() async {
    if (widget.dbService == null) return;

    final svc = CheatDayService(widget.dbService!);
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

  /// Opens the share progress sheet (cloud-only feature).
  void _showShareSheet(BuildContext context, AppLocalizations l, int streak, int bestStreak) {
    if (!AppFeatures.shareProgress) return;

    final store = DataStore.instance;

    // Calculate today's nutrition totals
    final todayCalories = store.foodEntries.fold<double>(0, (sum, e) => sum + e.calories);
    final todayProtein = store.foodEntries.fold<double>(0, (sum, e) => sum + e.protein);
    final todayFat = store.foodEntries.fold<double>(0, (sum, e) => sum + e.fat);
    final todayCarbs = store.foodEntries.fold<double>(0, (sum, e) => sum + e.carbs);

    final goal = store.goal;
    final todayDate = _selectedDay;

    premiumFeatures.showShareProgressSheet(
      context: context,
      streak: streak,
      bestStreak: bestStreak,
      date: todayDate,
      todayCalories: todayCalories,
      todayProtein: todayProtein,
      todayFat: todayFat,
      todayCarbs: todayCarbs,
      goalCalories: goal?.calories,
      goalProtein: goal?.protein,
      goalFat: goal?.fat,
      goalCarbs: goal?.carbs,
      shareButtonLabel: l.shareButton,
      sharingLabel: l.sharing,
    );
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
      appLogger.w('⚠️ Kann nicht in die Zukunft blättern (heute ist ${today.toIso8601String().split('T')[0]})');
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
      bool hasGoal = false;

      if (widget.dbService != null) {
        // Remote mode: check with NutritionGoalService
        final goalService = NutritionGoalService(widget.dbService!);
        hasGoal = await goalService.hasGoalForDate(newDay);
      } else {
        // Guest mode: check with LocalDataService
        final localGoal = await LocalDataService.instance.getGoalForDate(newDay);
        hasGoal = localGoal != null;
      }

      if (!mounted) return;  // ✅ Prüfe nach async Operation

      if (!hasGoal) {
        appLogger.w('⚠️ Kein Goal für ${newDay.toIso8601String().split('T')[0]} gefunden');
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
                if (widget.isGuestMode)
                  FilledButton.icon(
                    onPressed: () async {
                      // Navigate to GoalRecommendationScreen for guest mode
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GoalRecommendationScreen(
                            dbService: null,
                          ),
                        ),
                      );
                      // Nach Rückkehr: Goal neu laden
                      _loadCurrentGoal();
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l.createGoal),
                  )
                else if (widget.dbService != null)
                  FilledButton.icon(
                    onPressed: () async {
                      // Navigiere zu Goal-Empfehlung
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GoalRecommendationScreen(
                            dbService: widget.dbService!,
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
    
    // Build FAB based on selected tab
    Widget? fab;
    if (_selectedIndex == 3 && HealthConnectService.isSupported && widget.dbService != null) {
      fab = FloatingActionButton(
        heroTag: 'fab_reports_health_connect',
        onPressed: () => _importBodyWeightsFromHealthConnect(context),
        tooltip: l.importHealthConnect,
        child: const Icon(Icons.health_and_safety_outlined),
      );
    } else if (_selectedIndex == 2) {
      final db = widget.dbService;
      fab = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (HealthConnectService.isSupported) ...[
            FloatingActionButton(
              heroTag: 'fab_health_connect',
              onPressed: () => _importFromHealthConnect(context),
              tooltip: l.importHealthConnect,
              child: const Icon(Icons.health_and_safety_outlined),
            ),
            const SizedBox(width: 12),
          ],
          if (db != null) ...[
            FloatingActionButton(
              heroTag: 'fab_activity_database',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ActivityDatabaseScreen(dbService: db),
              )),
              tooltip: l.myActivities,
              child: const Icon(Icons.storage_outlined),
            ),
            const SizedBox(width: 12),
          ],
          if (AppFeatures.activityQuickAdd && db != null) ...[
            FloatingActionButton(
              heroTag: 'fab_activity_quick_add',
              onPressed: _showActivityQuickAdd,
              tooltip: l.activityQuickAdd,
              child: const Icon(Icons.bolt),
            ),
            const SizedBox(width: 12),
          ],
          if (MediaQuery.of(context).size.width >= 550)
            FloatingActionButton.extended(
              heroTag: 'fab_add_activity',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AddActivityScreen(dbService: db, selectedDate: _selectedDay),
              )),
              icon: const Icon(Icons.add),
              label: Text(l.addActivity),
            )
          else
            FloatingActionButton(
              heroTag: 'fab_add_activity',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AddActivityScreen(dbService: db, selectedDate: _selectedDay),
              )),
              tooltip: l.addActivity,
              child: const Icon(Icons.add),
            ),
        ],
      );
    } else if (_selectedIndex == 1) {
      // Food Entries tab
      final db = widget.dbService;
      final jwt = db?.jwt;
      final userId = db?.userId;
      final isAuthenticated = !widget.isGuestMode && db != null;

      if (isAuthenticated) {
        final hasMealTemplates = AppFeatures.mealTemplates && jwt != null && userId != null;
        fab = Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (hasMealTemplates) ...[
              FloatingActionButton(
                heroTag: 'fab_meal_templates',
                onPressed: () async {
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (ctx) => FractionallySizedBox(
                      heightFactor: 0.85,
                      child: premiumFeatures.buildMealTemplatesSheet(
                        userId: userId,
                        date: _selectedDay,
                        authToken: jwt,
                        dataApiUrl: NeonDatabaseService.dataApiUrl,
                        onLog: (data) async {
                          final now = DateTime.now();
                          final entry = FoodEntry(
                            id: '',
                            userId: userId,
                            mealTemplateId: data.id,
                            entryDate: _selectedDay,
                            mealType: MealType.fromJson(data.mealType),
                            name: data.name,
                            amount: data.amount,
                            unit: data.unit,
                            calories: data.calories,
                            protein: data.protein,
                            fat: data.fat,
                            carbs: data.carbs,
                            fiber: data.fiber,
                            sugar: data.sugar,
                            sodium: data.sodium,
                            isMeal: true,
                            createdAt: now,
                            updatedAt: now,
                          );
                          await _sync.createFoodEntry(entry);
                          await _store.loadDay(_selectedDay, silent: true, delta: true);
                        },
                      ),
                    ),
                  );
                },
                tooltip: l.mealTemplates,
                child: const Icon(Icons.restaurant_menu),
              ),
              const SizedBox(width: 12),
            ],
            FloatingActionButton(
              heroTag: 'fab_food_database',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FoodDatabaseScreen(dbService: db),
              )),
              tooltip: l.myFoods,
              child: const Icon(Icons.storage_outlined),
            ),
            const SizedBox(width: 12),
            FloatingActionButton(
              heroTag: 'fab_quick_entry',
              onPressed: () async {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (ctx) => FractionallySizedBox(
                    heightFactor: 0.85,
                    child: QuickFoodEntrySheet(
                      dbService: db,
                      date: _selectedDay,
                      initialMealType: _suggestMealType(),
                      onAdd: (entry) async {
                        await _sync.createFoodEntry(entry);
                        await _store.loadDay(_selectedDay, silent: true, delta: true);
                      },
                    ),
                  ),
                );
              },
              tooltip: l.addEntry,
              child: const Icon(Icons.bolt),
            ),
            const SizedBox(width: 12),
            if (MediaQuery.of(context).size.width >= 550)
              FloatingActionButton.extended(
                heroTag: 'fab_add_entry',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AddFoodEntryScreen(
                    dbService: db,
                    selectedDate: _selectedDay,
                  ),
                )),
                icon: const Icon(Icons.add),
                label: Text(l.addEntry),
              )
            else
              FloatingActionButton(
                heroTag: 'fab_add_entry',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AddFoodEntryScreen(
                    dbService: db,
                    selectedDate: _selectedDay,
                  ),
                )),
                tooltip: l.addEntry,
                child: const Icon(Icons.add),
              ),
          ],
        );
      } else {
        // Guest mode: single FAB → full entry form
        fab = FloatingActionButton(
          heroTag: 'fab_add_entry',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AddFoodEntryScreen(
              dbService: widget.dbService,
              selectedDate: _selectedDay,
            ),
          )),
          tooltip: l.addEntry,
          child: const Icon(Icons.add),
        );
      }
    }

    return Scaffold(
      floatingActionButton: fab,
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
                liquidFoodIntakeMl: _store.liquidFoodIntakeMl,
                selectedDay: _selectedDay,
                onChangeDay: _changeDay,
                onJumpToToday: _jumpToToday,
                onWaterChanged: _onWaterChanged,
                dbService: widget.dbService,
                isCheatDay: _store.isCheatDay,
                streak: _store.streak,
                bestStreak: _store.bestStreak,
                onToggleCheatDay: _toggleCheatDay,
                onShareProgress: AppFeatures.shareProgress
                    ? () => _showShareSheet(context, AppLocalizations.of(context)!, _store.streak, _store.bestStreak)
                    : null,
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
              ReportsScreen(
                dbService: widget.dbService,
                goal: _store.goal,
                refreshTrigger: _reportsRefreshTrigger,
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
          if (index == 3 && _selectedIndex != 3) {
            _reportsRefreshTrigger.value++;
          }
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
          BottomNavigationBarItem(
            icon: const Icon(Icons.bar_chart),
            label: l.navReports,
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
  final int liquidFoodIntakeMl;
  final DateTime selectedDay;
  final void Function(int offset) onChangeDay;
  final VoidCallback onJumpToToday;
  final void Function(int deltaMl) onWaterChanged;
  final NeonDatabaseService? dbService;
  final bool isCheatDay;
  final int streak;
  final int bestStreak;
  final Future<void> Function() onToggleCheatDay;
  final VoidCallback? onShareProgress;

  const OverviewScreen({
    super.key,
    required this.goal,
    required this.entries,
    required this.activities,
    required this.waterIntakeMl,
    required this.liquidFoodIntakeMl,
    required this.selectedDay,
    required this.onChangeDay,
    required this.onJumpToToday,
    required this.onWaterChanged,
    required this.dbService,
    required this.isCheatDay,
    required this.streak,
    required this.bestStreak,
    required this.onToggleCheatDay,
    this.onShareProgress,
  });

  // Berechne Gesamt-Nährwerte aus entries
  double get totalCalories => entries.fold(0, (sum, e) => sum + e.calories);
  double get totalProtein => entries.fold(0, (sum, e) => sum + e.protein);
  double get totalFat => entries.fold(0, (sum, e) => sum + e.fat);
  double get totalCarbs => entries.fold(0, (sum, e) => sum + e.carbs);

  // ✅ Berechne verbrannte Kalorien aus activities
  double get totalCaloriesBurned => activities.fold(0.0, (sum, a) => sum + (a.caloriesBurned ?? 0));

  String _formatRemainingCalories(double remaining, AppLocalizations l) {
    final absValue = remaining.abs().toStringAsFixed(0);
    if (remaining >= 0) {
      return '$absValue kcal';
    } else {
      return l.caloriesTooMuch(absValue);
    }
  }

  Widget _buildNutrientCard(
    BuildContext context,
    String label,
    String goalValue,
    String consumedValue,
    String burnedValue,
    String remainingValue,
    Color? color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (color != null)
                  Container(
                    width: 8,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.goal,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        goalValue,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.consumed,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        consumedValue,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (burnedValue != '-')
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.caloriesBurned,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          burnedValue,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)!.remaining,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    remainingValue,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: remainingValue.contains('too much') || remainingValue.contains('zu viel') || remainingValue.contains('demasiado')
                          ? Colors.red
                          : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionOverview(BuildContext context, AppLocalizations l) {
    final remainingCalories = goal.calories - totalCalories + totalCaloriesBurned;
    final remainingProtein = (goal.protein - totalProtein).clamp(0, goal.protein);
    final remainingFat = (goal.fat - totalFat).clamp(0, goal.fat);
    final remainingCarbs = (goal.carbs - totalCarbs).clamp(0, goal.carbs);

    final isMobile = MediaQuery.of(context).size.width < 550;

    if (isMobile) {
      // Mobile: Card-based layout
      return Column(
        children: [
          if (!goal.macroOnly)
            _buildNutrientCard(
              context,
              l.nutrientCalories,
              '${goal.calories.toStringAsFixed(0)} kcal',
              '${totalCalories.toStringAsFixed(0)} kcal',
              totalCaloriesBurned > 0 ? '${totalCaloriesBurned.toStringAsFixed(0)} kcal' : '-',
              _formatRemainingCalories(remainingCalories, l),
              Colors.deepPurple,
            ),
          _buildNutrientCard(
            context,
            l.nutrientProtein,
            '${goal.protein.toStringAsFixed(1)} g',
            '${totalProtein.toStringAsFixed(1)} g',
            '-',
            '${remainingProtein.toStringAsFixed(1)} g',
            Colors.red,
          ),
          _buildNutrientCard(
            context,
            l.nutrientFat,
            '${goal.fat.toStringAsFixed(1)} g',
            '${totalFat.toStringAsFixed(1)} g',
            '-',
            '${remainingFat.toStringAsFixed(1)} g',
            Colors.orange,
          ),
          _buildNutrientCard(
            context,
            l.nutrientCarbs,
            '${goal.carbs.toStringAsFixed(1)} g',
            '${totalCarbs.toStringAsFixed(1)} g',
            '-',
            '${remainingCarbs.toStringAsFixed(1)} g',
            Colors.amber,
          ),
        ],
      );
    } else {
      // Desktop/Medium: Table layout (with horizontal scroll on medium screens)
      final table = DataTable(
        horizontalMargin: 12,
        columnSpacing: 12,
        columns: [
          const DataColumn(label: Text('')),
          DataColumn(label: Text(l.goal, overflow: TextOverflow.ellipsis)),
          DataColumn(label: Text(l.consumed, overflow: TextOverflow.ellipsis)),
          DataColumn(label: Text(l.caloriesBurned, overflow: TextOverflow.ellipsis)),
          DataColumn(label: Text(l.remaining, overflow: TextOverflow.ellipsis)),
        ],
        rows: [
          if (!goal.macroOnly)
            DataRow(cells: [
              DataCell(Text(l.nutrientCalories, overflow: TextOverflow.ellipsis)),
              DataCell(Text(goal.calories.toStringAsFixed(0), overflow: TextOverflow.ellipsis)),
              DataCell(Text(totalCalories.toStringAsFixed(0), overflow: TextOverflow.ellipsis)),
              DataCell(Text(
                totalCaloriesBurned.toStringAsFixed(0),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.green.shade700),
              )),
              DataCell(Text(
                _formatRemainingCalories(remainingCalories, l),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: remainingCalories >= 0 ? Colors.green : Colors.red,
                ),
              )),
            ]),
          DataRow(cells: [
            DataCell(Text(l.nutrientProtein, overflow: TextOverflow.ellipsis)),
            DataCell(Text(goal.protein.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
            DataCell(Text(totalProtein.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
            const DataCell(Text('-', overflow: TextOverflow.ellipsis)),
            DataCell(Text(remainingProtein.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
          ]),
          DataRow(cells: [
            DataCell(Text(l.nutrientFat, overflow: TextOverflow.ellipsis)),
            DataCell(Text(goal.fat.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
            DataCell(Text(totalFat.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
            const DataCell(Text('-', overflow: TextOverflow.ellipsis)),
            DataCell(Text(remainingFat.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
          ]),
          DataRow(cells: [
            DataCell(Text(l.nutrientCarbs, overflow: TextOverflow.ellipsis)),
            DataCell(Text(goal.carbs.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
            DataCell(Text(totalCarbs.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
            const DataCell(Text('-', overflow: TextOverflow.ellipsis)),
            DataCell(Text(remainingCarbs.toStringAsFixed(1), overflow: TextOverflow.ellipsis)),
          ]),
        ],
      );

      // Wrap in horizontal scroll if screen is narrower than 700px
      if (MediaQuery.of(context).size.width < 700) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        );
      }
      return table;
    }
  }

  Widget _buildWaterCard(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final waterGoal = goal.waterGoalMl ?? 2000;
    final totalLiquidMl = waterIntakeMl + liquidFoodIntakeMl;
    final progress = (totalLiquidMl / waterGoal).clamp(0.0, 1.0);

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
                Flexible(
                  child: Text(
                    '$totalLiquidMl ml',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l.waterGoalLabel(waterGoal),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            // Show breakdown if there's liquid food contribution
            if (liquidFoodIntakeMl > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '💧 $waterIntakeMl ml ${l.waterManual} · 🥤 $liquidFoodIntakeMl ml ${l.waterFromFood}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            _WaterAmountControls(
              waterIntakeMl: waterIntakeMl,
              onWaterChanged: onWaterChanged,
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
                GestureDetector(
                  onTap: onShareProgress,
                  child: Tooltip(
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

          if (!goal.macroOnly) ...[
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
                Flexible(
                  child: Text(
                    '${l.consumed}: ${totalCalories.toStringAsFixed(0)} kcal',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (totalCaloriesBurned > 0) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${l.caloriesBurned}: ${totalCaloriesBurned.toStringAsFixed(0)} kcal',
                      style: TextStyle(color: Colors.green.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    '${l.goal}: ${goal.calories.toStringAsFixed(0)} kcal',
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            Text(
              '${l.remaining}: ${_formatRemainingCalories(goal.calories - totalCalories + totalCaloriesBurned, l)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: (goal.calories - totalCalories + totalCaloriesBurned) >= 0
                    ? Colors.green
                    : Colors.red,
              ),
            ),
          ],
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
          // Responsive nutrition overview (cards on mobile, table on desktop)
          _buildNutritionOverview(context, l),
          // Mikronährstoff-Karte (Premium, konfigurierbar)
          if (AppFeatures.microNutrients && dbService != null) ...[
            const SizedBox(height: 24),
            Builder(builder: (context) {
              final jwt = dbService!.jwt;
              final userId = dbService!.userId;
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

// Water intake +/− controls with selectable step (100 / 200 / 300 ml)
class _WaterAmountControls extends StatefulWidget {
  final int waterIntakeMl;
  final void Function(int deltaMl) onWaterChanged;

  const _WaterAmountControls({
    required this.waterIntakeMl,
    required this.onWaterChanged,
  });

  @override
  State<_WaterAmountControls> createState() => _WaterAmountControlsState();
}

class _WaterAmountControlsState extends State<_WaterAmountControls> {
  int _selectedMl = 200;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width < 550;

    if (isMobile) {
      // Mobile: Simplified view with +/- buttons only (200 ml fixed)
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filled(
            icon: const Icon(Icons.remove),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue.shade100,
              foregroundColor: Colors.blue,
            ),
            tooltip: l.waterRemove,
            onPressed: widget.waterIntakeMl >= 200
                ? () => widget.onWaterChanged(-200)
                : null,
          ),
          const SizedBox(width: 16),
          Text(
            '200 ml',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          IconButton.filled(
            icon: const Icon(Icons.add),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            tooltip: l.waterAdd,
            onPressed: () => widget.onWaterChanged(200),
          ),
        ],
      );
    }

    // Desktop: Full controls with selector
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filled(
          icon: const Icon(Icons.remove),
          style: IconButton.styleFrom(
            backgroundColor: Colors.blue.shade100,
            foregroundColor: Colors.blue,
          ),
          tooltip: l.waterRemove,
          onPressed: widget.waterIntakeMl >= _selectedMl
              ? () => widget.onWaterChanged(-_selectedMl)
              : null,
        ),
        const SizedBox(width: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 100, label: Text('100')),
            ButtonSegment(value: 200, label: Text('200')),
            ButtonSegment(value: 300, label: Text('300')),
          ],
          selected: {_selectedMl},
          onSelectionChanged: (s) => setState(() => _selectedMl = s.first),
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'ml',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          tooltip: l.waterAdd,
          onPressed: () => widget.onWaterChanged(_selectedMl),
        ),
      ],
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
                              trailing: entry.isLiquid && entry.unit == 'ml'
                                  ? const Icon(Icons.water_drop, color: Colors.lightBlue, size: 20)
                                  : null,
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
