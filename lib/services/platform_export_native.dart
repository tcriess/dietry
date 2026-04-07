import 'dart:io';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Saves CSV files:
///   - Desktop (Linux/Win/macOS): lets user pick a directory, then writes files there.
///   - Mobile (Android/iOS):      opens system share sheet.
Future<void> exportCsvFiles({
  required String timestamp,
  required Map<String, String> files,
}) async {
  final isDesktop = defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  if (isDesktop) {
    // Let user pick the destination directory; fall back to Downloads on error/cancel.
    String? selectedDir;
    try {
      selectedDir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Exportverzeichnis wählen',
        lockParentWindow: true,
      );
    } catch (_) {}

    if (selectedDir == null) {
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      dir ??= await getTemporaryDirectory();
      selectedDir = dir.path;
    }

    for (final entry in files.entries) {
      await File('$selectedDir/${entry.key}').writeAsString(entry.value);
    }

    try {
      await launchUrl(Uri.parse('file://$selectedDir'));
    } catch (_) {}
  } else {
    // Mobile: share sheet.
    final temp = await getTemporaryDirectory();
    final xfiles = <XFile>[];
    for (final entry in files.entries) {
      final f = File('${temp.path}/${entry.key}');
      await f.writeAsString(entry.value);
      xfiles.add(XFile(f.path, mimeType: 'text/csv'));
    }
    await SharePlus.instance.share(
      ShareParams(files: xfiles, subject: 'Dietry Datenexport $timestamp'),
    );
  }
}
