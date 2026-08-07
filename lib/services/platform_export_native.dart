import 'dart:io';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Saves a single text file of any type (used for the .ics calendar export).
/// Same destinations as [exportCsvFiles]: a chosen folder on desktop, the
/// share sheet on mobile.
Future<void> exportTextFile({
  required String filename,
  required String content,
  required String mimeType,
}) async {
  if (_isDesktop) {
    final dir = await _pickOrDefaultDirectory();
    await File('$dir/$filename').writeAsString(content);
    try {
      await launchUrl(Uri.parse('file://$dir'));
    } catch (_) {}
    return;
  }

  final temp = await getTemporaryDirectory();
  final file = File('${temp.path}/$filename');
  await file.writeAsString(content);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
  );
}

/// The directory the user picked, falling back to Downloads (then temp) when
/// they cancel or the picker fails.
Future<String> _pickOrDefaultDirectory() async {
  String? selectedDir;
  try {
    selectedDir = await getDirectoryPath();
  } catch (_) {}
  if (selectedDir != null) return selectedDir;

  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getTemporaryDirectory();
  return dir.path;
}

/// Saves CSV files:
///   - Desktop (Linux/Win/macOS): lets user pick a directory, then writes files there.
///   - Mobile (Android/iOS):      opens system share sheet.
Future<void> exportCsvFiles({
  required String timestamp,
  required Map<String, String> files,
}) async {
  final isDesktop = _isDesktop;

  if (isDesktop) {
    // Let user pick the destination directory; fall back to Downloads on error/cancel.
    String? selectedDir;
    try {
      // No custom button label — the native folder picker uses the OS's own
      // localized "Select"/"Choose" label (avoids a hard-coded, untranslated
      // string). file_selector's getDirectoryPath has no dialog-title option.
      selectedDir = await getDirectoryPath();
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
