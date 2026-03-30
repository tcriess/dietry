import 'package:flutter/material.dart';
import '../services/neon_database_service.dart';
import '../services/nutrition_goal_service.dart';
import '../models/models.dart';

/// Debug-Screen zum Testen der Goal-Speicherung
/// 
/// Testet:
/// - Goal INSERT (erstes Mal für Datum)
/// - Goal UPDATE (zweites Mal für gleiches Datum)
/// - UPSERT Funktionalität
class GoalSaveDebugScreen extends StatefulWidget {
  final NeonDatabaseService dbService;

  const GoalSaveDebugScreen({
    super.key,
    required this.dbService,
  });

  @override
  State<GoalSaveDebugScreen> createState() => _GoalSaveDebugScreenState();
}

class _GoalSaveDebugScreenState extends State<GoalSaveDebugScreen> {
  final _logs = <String>[];
  bool _isRunning = false;

  void _log(String message) {
    setState(() {
      _logs.add('${DateTime.now().toIso8601String().split('.')[0]} - $message');
    });
    print(message);
  }

  Future<void> _runTest() async {
    setState(() {
      _isRunning = true;
      _logs.clear();
    });

    try {
      final goalService = NutritionGoalService(widget.dbService);
      _log('🔍 Test 1: Prüfe aktuelles Goal');
      final currentGoal = await goalService.getCurrentGoal();
      if (currentGoal != null) {
        _log('✅ Aktuelles Goal gefunden: ${currentGoal.calories.toInt()} kcal');
        _log('   Valid from: ${currentGoal.validFrom}');
      } else {
        _log('ℹ️ Kein aktuelles Goal vorhanden');
      }

      _log('');
      _log('🔍 Test 2: Erstelle neues Goal für heute');
      final testGoal1 = NutritionGoal(
        calories: 2000.0,
        protein: 150.0,
        fat: 65.0,
        carbs: 200.0,
      );

      try {
        final saved1 = await goalService.createOrUpdateGoal(testGoal1);
        _log('✅ Goal 1 gespeichert: ${saved1.calories.toInt()} kcal');
        _log('   ID: ${saved1.id}');
      } catch (e) {
        _log('❌ Fehler beim Speichern von Goal 1: $e');
      }

      _log('');
      _log('🔍 Test 3: Aktualisiere Goal für heute (gleicher Tag!)');
      final testGoal2 = NutritionGoal(
        calories: 2200.0,
        protein: 165.0,
        fat: 70.0,
        carbs: 220.0,
      );

      try {
        final saved2 = await goalService.createOrUpdateGoal(testGoal2);
        _log('✅ Goal 2 gespeichert (UPDATE): ${saved2.calories.toInt()} kcal');
        _log('   ID: ${saved2.id}');
        _log('   Sollte gleiche ID haben wie Goal 1!');
      } catch (e) {
        _log('❌ Fehler beim Speichern von Goal 2: $e');
      }

      _log('');
      _log('🔍 Test 4: Hole alle Goals');
      final allGoals = await goalService.getAllGoals();
      _log('✅ ${allGoals.length} Goals gefunden');
      for (final goal in allGoals) {
        _log('   - ${goal.validFrom}: ${goal.calories.toInt()} kcal');
      }

      _log('');
      _log('✅ Test abgeschlossen!');
    } catch (e, stackTrace) {
      _log('❌ Test fehlgeschlagen: $e');
      _log('Stack trace: $stackTrace');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal Save Debug'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Goal UPSERT Test',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Testet ob Goals korrekt gespeichert/aktualisiert werden:',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '1. Erstelle Goal für heute (INSERT)\n'
                          '2. Aktualisiere Goal für heute (UPDATE)\n'
                          '3. Prüfe ob nur 1 Goal für heute existiert',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isRunning ? null : _runTest,
                  icon: _isRunning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isRunning ? 'Test läuft...' : 'Test starten'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('Klicke "Test starten" um zu beginnen'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      Color? color;
                      IconData? icon;

                      if (log.contains('✅')) {
                        color = Colors.green;
                        icon = Icons.check_circle;
                      } else if (log.contains('❌')) {
                        color = Colors.red;
                        icon = Icons.error;
                      } else if (log.contains('⚠️')) {
                        color = Colors.orange;
                        icon = Icons.warning;
                      } else if (log.contains('🔍')) {
                        color = Colors.blue;
                        icon = Icons.search;
                      } else {
                        icon = Icons.info_outline;
                      }

                      return Card(
                        color: color?.withValues(alpha: 0.1),
                        child: ListTile(
                          dense: true,
                          leading: Icon(icon, color: color, size: 20),
                          title: Text(
                            log,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: color,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

