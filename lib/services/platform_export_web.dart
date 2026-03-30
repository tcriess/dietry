import 'package:web/web.dart' as web;
import 'dart:js_interop';

/// Triggers CSV file downloads in the browser, one per file.
Future<void> exportCsvFiles({
  required String timestamp,
  required Map<String, String> files,
}) async {
  for (final entry in files.entries) {
    _triggerDownload(entry.key, entry.value);
    // Small delay so browsers don't block multiple simultaneous downloads.
    await Future.delayed(const Duration(milliseconds: 200));
  }
}

void _triggerDownload(String filename, String content) {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = filename;
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
