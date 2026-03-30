// Dummy für Nicht-Web-Plattformen, damit der Import funktioniert
import 'dart:async';

class WindowBase {
  dynamic open(String url, String name, [String? features]) => null;
  Stream<MessageEvent> get onMessage => Stream<MessageEvent>.empty();
}

class MessageEvent {
  final dynamic data;
  MessageEvent(this.data);
}

final WindowBase window = WindowBase();

// Exports für Kompatibilität
class Window extends WindowBase {}

// Stub-Funktion für jsObjectToDartMap (wird nur auf Native aufgerufen, wenn kIsWeb false)
Map<String, dynamic>? jsObjectToDartMap(dynamic jsObject) {
  // Auf nativen Plattformen wird diese Funktion nie aufgerufen,
  // da der Web-spezifische Code durch kIsWeb-Guards geschützt ist
  throw UnsupportedError('jsObjectToDartMap ist nur im Web verfügbar');
}

// Stub-Funktion für fetchWithCredentials (wird nur auf Web verwendet)
Future<Map<String, dynamic>> fetchWithCredentials(String url) async {
  throw UnsupportedError('fetchWithCredentials ist nur im Web verfügbar');
}

// Stub-Funktionen für Web-only Helpers (für Native-Plattformen)
String? getFromLocalStorage(String key) {
  throw UnsupportedError('localStorage ist nur im Web verfügbar');
}

void removeFromLocalStorage(String key) {
  throw UnsupportedError('localStorage ist nur im Web verfügbar');
}

void setToLocalStorage(String key, String value) {
  throw UnsupportedError('localStorage ist nur im Web verfügbar');
}

void browserRedirect(String url) {
  throw UnsupportedError('browserRedirect ist nur im Web verfügbar');
}

void browserReplaceState(String url) {
  throw UnsupportedError('browserReplaceState ist nur im Web verfügbar');
}

Future<bool> requestBrowserNotificationPermission() async => false;
bool get browserNotificationsGranted => false;
void showBrowserNotification(String title, String body) {}
