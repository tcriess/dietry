// Web-spezifische Imports mit den neuen Web-APIs
// package:web ist der Ersatz für das deprecated dart:html
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:async';

// Re-exports für Kompatibilität mit dem bestehenden Code
web.Window get window => web.window;

// Helper-Funktion: Browser fetch() mit credentials: 'include'
// Sendet HttpOnly Cookies automatisch mit!
Future<Map<String, dynamic>> fetchWithCredentials(String url) async {
  final response = await window.fetch(
    url.toJS,
    web.RequestInit(
      method: 'GET',
      credentials: 'include',  // ← Sendet Cookies automatisch!
      headers: {
        'Accept': 'application/json',
      }.jsify() as JSObject,
    ),
  ).toDart;
  
  final statusCode = response.status;
  final bodyText = await response.text().toDart;
  
  // ✅ Extrahiere alle Response Headers
  final headers = <String, String>{};
  
  // Wichtige Header einzeln auslesen
  // Headers.get() gibt direkt String zurück, keine JS-Konvertierung nötig!
  try {
    final setAuthJwt = response.headers.get('set-auth-jwt');
    if (setAuthJwt != null && setAuthJwt.isNotEmpty) {
      headers['set-auth-jwt'] = setAuthJwt;
    }
  } catch (e) {
    // Ignore - Header nicht vorhanden
  }
  
  try {
    final contentType = response.headers.get('content-type');
    if (contentType != null && contentType.isNotEmpty) {
      headers['content-type'] = contentType;
    }
  } catch (e) {
    // Ignore
  }
  
  return {
    'statusCode': statusCode,
    'body': bodyText,
    'headers': headers,
    'ok': response.ok,
  };
}

// Helper-Funktionen für Web-spezifische APIs (nur im Web verfügbar)

/// Lese aus localStorage (nur Web)
String? getFromLocalStorage(String key) {
  return window.localStorage.getItem(key);
}

/// Entferne aus localStorage (nur Web)
void removeFromLocalStorage(String key) {
  window.localStorage.removeItem(key);
}

/// Schreibt einen Wert in localStorage (nur Web)
void setToLocalStorage(String key, String value) {
  window.localStorage.setItem(key, value);
}

/// Redirect im Browser (nur Web)
void browserRedirect(String url) {
  window.location.href = url;
}

/// History replaceState (nur Web)
void browserReplaceState(String url) {
  window.history.replaceState(null, '', url);
}

// MessageEvent aus package:web
typedef MessageEvent = web.MessageEvent;

// Window-Typ exportieren
typedef Window = web.Window;

// Helper-Funktion: Konvertiere JS-Objekt zu Dart-Map
Map<String, dynamic>? jsObjectToDartMap(JSAny? jsObject) {
  if (jsObject == null) return null;
  
  try {
    final obj = jsObject as JSObject;
    final map = <String, dynamic>{};
    
    // Liste der erwarteten Properties (für auth_callback)
    final knownKeys = ['type', 'token', 'verifier', 'success', 'session', 'user'];
    
    for (final key in knownKeys) {
      try {
        final value = obj.getProperty(key.toJS);
        
        if (value != null) {
          // Konvertiere Werte zu Dart-Typen
          if (value.typeofEquals('string')) {
            map[key] = (value as JSString).toDart;
          } else if (value.typeofEquals('number')) {
            map[key] = (value as JSNumber).toDartDouble;
          } else if (value.typeofEquals('boolean')) {
            map[key] = (value as JSBoolean).toDart;
          } else if (value.typeofEquals('object')) {
            // Rekursiv für verschachtelte Objekte (z.B. session, user)
            map[key] = jsObjectToDartMap(value);
          } else {
            // Fallback: Versuche toString
            map[key] = value.toString();
          }
        }
      } catch (_) {
        // Property existiert nicht, überspringen
        continue;
      }
    }
    
    // Wenn wir mindestens ein Property gefunden haben, gib die Map zurück
    return map.isNotEmpty ? map : null;
  } catch (e) {
    // Nur kritische Fehler loggen
    print('⚠️ jsObjectToDartMap Fehler: $e');
    return null;
  }
}

// Helper-Extension für onMessage Stream (für Kompatibilität mit altem Code)
extension WindowMessageExtension on web.Window {
  Stream<web.MessageEvent> get onMessage {
    final controller = StreamController<web.MessageEvent>.broadcast();

    void handleMessage(web.Event event) {
      // Cast direkt zu MessageEvent (event ist immer MessageEvent bei 'message' Events)
      controller.add(event as web.MessageEvent);
    }

    addEventListener('message', handleMessage.toJS);

    // TODO: removeEventListener when stream is cancelled
    return controller.stream;
  }
}

/// Fragt Browser-Notification-Berechtigung an (Web).
/// Gibt true zurück wenn Berechtigung erteilt wurde.
Future<bool> requestBrowserNotificationPermission() async {
  if (web.Notification.permission == 'granted') return true;
  if (web.Notification.permission == 'denied') return false;
  final result = await web.Notification.requestPermission().toDart;
  return result.toDart == 'granted';
}

/// Gibt zurück ob Browser-Notifications erlaubt sind.
bool get browserNotificationsGranted =>
    web.Notification.permission == 'granted';

/// Zeigt eine Browser-Notification (Web).
void showBrowserNotification(String title, String body) {
  if (web.Notification.permission != 'granted') return;
  web.Notification(title, web.NotificationOptions(body: body));
}
