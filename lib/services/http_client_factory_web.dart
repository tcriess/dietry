import 'package:http/browser_client.dart';
import 'package:http/http.dart';

/// On web: BrowserClient with withCredentials=true so the browser stores and
/// sends session cookies for cross-origin auth requests automatically.
Client createAuthHttpClient() => BrowserClient()..withCredentials = true;
