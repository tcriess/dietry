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
  databaseFactory = databaseFactoryFfiWeb;
}
