import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_shortcut.dart';

/// Speichert und lädt Food-Shortcuts lokal (SharedPreferences).
///
/// Shortcuts sind gerätespezifisch und werden nicht synchronisiert.
class FoodShortcutsService {
  static const _prefsKey = 'food_shortcuts_v1';

  static Future<List<FoodShortcut>> loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw.map(FoodShortcut.fromJsonString).toList();
  }

  static Future<void> saveShortcuts(List<FoodShortcut> shortcuts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _prefsKey, shortcuts.map((s) => s.toJsonString()).toList());
  }

  static Future<void> addShortcut(FoodShortcut shortcut) async {
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
