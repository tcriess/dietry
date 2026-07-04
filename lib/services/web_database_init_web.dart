// Web implementation, selected by the conditional import in main.dart (this is
// the default; native/desktop swap to web_database_init_stub.dart when
// `dart.library.io` is available).
//
// Routes sqflite through the IndexedDB/WASM-backed ffi_web factory so
// LocalDataService's SQL runs unchanged in the browser. Requires the shared
// worker + sqlite3.wasm copied into web/ by
// `dart run sqflite_common_ffi_web:setup`.
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void initWebDatabaseFactory() {
  // No-web-worker factory: runs the sqlite3 WASM on the main thread with an
  // IndexedDB-backed VFS. The default shared-worker factory
  // (databaseFactoryFfiWeb) failed to initialize in the browser with
  // "unsupported result null" — it relies on a SharedWorker and often
  // cross-origin isolation (COOP/COEP headers). Our local DB is small
  // (guest/cache data), so main-thread execution is acceptable and needs no
  // worker or special headers. Only sqlite3.wasm is required (in web/).
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}
