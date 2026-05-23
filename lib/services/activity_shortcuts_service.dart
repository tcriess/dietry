import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_shortcut.dart';

/// Loads and persists activity shortcuts in SharedPreferences.
///
/// Shortcuts are device-local and intentionally not synchronised across
/// devices — they mirror [FoodShortcutsService] so the Quick Add sheets
/// behave the same on the food and activity side.
class ActivityShortcutsService {
  static const _prefsKey = 'activity_shortcuts_v1';

  static Future<List<ActivityShortcut>> loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw.map(ActivityShortcut.fromJsonString).toList();
  }

  static Future<void> saveShortcuts(List<ActivityShortcut> shortcuts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _prefsKey, shortcuts.map((s) => s.toJsonString()).toList());
  }

  static Future<void> addShortcut(ActivityShortcut shortcut) async {
    final list = await loadShortcuts();
    list.add(shortcut);
    await saveShortcuts(list);
  }

  static Future<void> removeShortcut(String id) async {
    final list = await loadShortcuts();
    list.removeWhere((s) => s.id == id);
    await saveShortcuts(list);
  }
}
