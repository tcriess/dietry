import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/neon_database_service.dart';
import '../services/nutrition_goal_service.dart';

/// Test-Screen für Nutrition Goals
class NutritionGoalsTestScreen extends StatefulWidget {
  final NeonDatabaseService dbService;

  const NutritionGoalsTestScreen({
    super.key,
    required this.dbService,
  });

  @override
  State<NutritionGoalsTestScreen> createState() => _NutritionGoalsTestScreenState();
}

class _NutritionGoalsTestScreenState extends State<NutritionGoalsTestScreen> {
  late NutritionGoalService _goalService;
  NutritionGoal? _currentGoal;
  List<NutritionGoal> _allGoals = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _goalService = NutritionGoalService(widget.dbService);
    _loadGoals();
  }

  Future<void> _loadGoals() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final current = await _goalService.getCurrentGoal();
      final all = await _goalService.getAllGoals();

      setState(() {
        _currentGoal = current;
        _allGoals = all;
        _isLoading = false;
      });

      print('✅ Goals geladen: ${all.length} gesamt');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      print('❌ Fehler beim Laden: $e');
    }
  }

  Future<void> _createTestGoal() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final testGoal = NutritionGoal(
        calories: 2000,
        protein: 150,
        fat: 70,
        carbs: 200,
      );

      await _goalService.createOrUpdateGoal(testGoal);

      print('✅ Test-Goal erstellt!');
      
      // Reload goals
      await _loadGoals();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      print('❌ Fehler beim Erstellen: $e');
    }
  }

  Future<void> _deleteGoal(String id) async {
    setState(() => _isLoading = true);

    try {
      await _goalService.deleteGoal(id);
      print('✅ Goal gelöscht!');
      await _loadGoals();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      print('❌ Fehler beim Löschen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition Goals Test'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGoals,
            tooltip: 'Neu laden',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _createTestGoal,
        tooltip: 'Test-Goal erstellen',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Fehler beim Laden',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadGoals,
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Goal
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber),
                      const SizedBox(width: 8),
                      const Text(
                        'Aktuelles Ziel',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_currentGoal != null)
                    _buildGoalDetails(_currentGoal!)
                  else
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Noch kein Ziel gesetzt',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // All Goals
          Row(
            children: [
              const Icon(Icons.list),
              const SizedBox(width: 8),
              Text(
                'Alle Ziele (${_allGoals.length})',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_allGoals.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.inbox, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Keine Ziele vorhanden',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _createTestGoal,
                        icon: const Icon(Icons.add),
                        label: const Text('Test-Goal erstellen'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ...(_allGoals.map((goal) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Text(
                        '${goal.calories.toInt()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    title: Text(
                      '${goal.calories.toInt()} kcal',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'P: ${goal.protein.toInt()}g | F: ${goal.fat.toInt()}g | C: ${goal.carbs.toInt()}g\n'
                      'Ab: ${goal.validFrom?.toString().split(' ')[0] ?? 'heute'}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _showDeleteDialog(goal),
                    ),
                  ),
                ))),
        ],
      ),
    );
  }

  Widget _buildGoalDetails(NutritionGoal goal) {
    return Column(
      children: [
        _buildGoalRow('Kalorien', '${goal.calories.toInt()} kcal', Icons.local_fire_department),
        _buildGoalRow('Protein', '${goal.protein.toInt()} g', Icons.egg),
        _buildGoalRow('Fett', '${goal.fat.toInt()} g', Icons.water_drop),
        _buildGoalRow('Kohlenhydrate', '${goal.carbs.toInt()} g', Icons.grass),
        if (goal.validFrom != null)
          _buildGoalRow(
            'Gültig ab',
            goal.validFrom!.toString().split(' ')[0],
            Icons.calendar_today,
          ),
      ],
    );
  }

  Widget _buildGoalRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(NutritionGoal goal) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Goal löschen?'),
        content: Text(
          'Möchten Sie das Goal mit ${goal.calories.toInt()} kcal wirklich löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteGoal(goal.id!);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}

