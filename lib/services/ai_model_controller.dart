import 'package:flutter/foundation.dart';
import 'package:dietry_cloud/dietry_cloud.dart' show premiumFeatures;

/// Owns the on-device model's download state as a process-wide singleton, so it
/// survives the settings tile scrolling out of view / rebuilding, and can't be
/// started twice concurrently. The tile is a pure observer of these notifiers —
/// it never holds download state itself.
class AiModelController {
  AiModelController._();
  static final AiModelController instance = AiModelController._();

  /// 0..1 while a download is running; null when idle.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  /// Whether the model is present and ready.
  final ValueNotifier<bool> downloaded = ValueNotifier<bool>(false);

  /// True after a failed download attempt (cleared when a new one starts).
  final ValueNotifier<bool> failed = ValueNotifier<bool>(false);

  bool _initialized = false;

  Listenable get listenable => Listenable.merge([progress, downloaded, failed]);

  bool get isDownloading => progress.value != null;

  /// Read the current on-disk state once (idempotent, re-entrancy-safe).
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    downloaded.value = await premiumFeatures.isModelDownloaded();
  }

  /// Start a download. No-op if one is already running (guards the double-tap /
  /// scroll-recreate race).
  Future<void> download() async {
    if (isDownloading) return;
    failed.value = false;
    progress.value = 0;
    try {
      await premiumFeatures.downloadModel(
        onProgress: (p) => progress.value = p.clamp(0.0, 1.0),
      );
      downloaded.value = true;
    } catch (_) {
      failed.value = true;
    } finally {
      progress.value = null;
    }
  }

  Future<void> delete() async {
    if (isDownloading) return;
    await premiumFeatures.deleteModel();
    downloaded.value = false;
  }
}
