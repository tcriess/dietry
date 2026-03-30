import 'package:flutter/material.dart';
import '../models/user_body_data.dart';
import '../services/user_profile_service.dart';
import '../services/user_body_measurements_service.dart';
import '../services/neon_database_service.dart';
import '../services/neon_auth_service.dart';
import 'profile_setup_screen.dart';
import 'add_body_measurement_screen.dart';

/// Profil-Screen mit Körperdaten und Einstellungen
class ProfileScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final NeonAuthService authService;
  
  const ProfileScreen({
    super.key,
    required this.dbService,
    required this.authService,
  });
  
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  UserBodyMeasurement? _currentMeasurement;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final profileService = UserProfileService(widget.dbService);
      final measurementService = UserBodyMeasurementsService(widget.dbService);
      
      final results = await Future.wait([
        profileService.getCurrentProfile(),
        measurementService.getCurrentMeasurement(),
      ]);
      
      if (mounted) {
        setState(() {
          _profile = results[0] as UserProfile?;
          _currentMeasurement = results[1] as UserBodyMeasurement?;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Fehler beim Laden: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _editProfile() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileSetupScreen(
          dbService: widget.dbService,
          existingProfile: _profile,
        ),
      ),
    );
    
    if (result == true) {
      _loadData();
    }
  }
  
  Future<void> _addOrEditMeasurement() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddBodyMeasurementScreen(
          dbService: widget.dbService,
          existingMeasurement: _currentMeasurement,
          selectedDate: DateTime.now(),
        ),
      ),
    );
    
    if (result == true) {
      _loadData();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Abmelden?'),
                  content: const Text('Möchtest du dich wirklich abmelden?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Abbrechen'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Abmelden'),
                    ),
                  ],
                ),
              );
              
              if (confirmed == true && mounted) {
                await widget.authService.signOut();
                await widget.dbService.clearSession();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Körperdaten Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Körperdaten',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            IconButton(
                              icon: Icon(_currentBodyData == null ? Icons.add : Icons.edit),
                              onPressed: _addOrEditBodyData,
                              tooltip: _currentBodyData == null ? 'Hinzufügen' : 'Bearbeiten',
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        if (_currentBodyData == null)
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.person_outline, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  'Keine Körperdaten vorhanden',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _addOrEditBodyData,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Daten eingeben'),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          // Gewicht
                          _buildDataRow(
                            icon: Icons.monitor_weight,
                            label: 'Gewicht',
                            value: '${_currentBodyData!.weight.toStringAsFixed(1)} kg',
                            color: Colors.blue,
                          ),
                          
                          // Größe
                          _buildDataRow(
                            icon: Icons.height,
                            label: 'Größe',
                            value: '${_currentBodyData!.height.toStringAsFixed(0)} cm',
                            color: Colors.green,
                          ),
                          
                          // Alter
                          _buildDataRow(
                            icon: Icons.cake,
                            label: 'Alter',
                            value: '${_currentBodyData!.age} Jahre',
                            color: Colors.purple,
                          ),
                          
                          // Geschlecht
                          _buildDataRow(
                            icon: Icons.person,
                            label: 'Geschlecht',
                            value: _currentBodyData!.gender.displayName,
                            color: Colors.indigo,
                          ),
                          
                          const Divider(height: 24),
                          
                          // Aktivitätslevel
                          _buildDataRow(
                            icon: Icons.directions_run,
                            label: 'Aktivitätslevel',
                            value: _currentBodyData!.activityLevel.displayName,
                            color: Colors.teal,
                          ),
                          
                          // Gewichtsziel
                          _buildDataRow(
                            icon: Icons.flag,
                            label: 'Gewichtsziel',
                            value: _currentBodyData!.weightGoal.displayName,
                            color: Colors.amber,
                          ),
                          
                          // BMR & TDEE
                          if (_currentBodyData!.bmr != null || _currentBodyData!.tdee != null) ...[
                            const Divider(height: 24),
                            if (_currentBodyData!.bmr != null)
                              _buildDataRow(
                                icon: Icons.local_fire_department,
                                label: 'BMR (Grundumsatz)',
                                value: '${_currentBodyData!.bmr!.toStringAsFixed(0)} kcal/Tag',
                                color: Colors.orange,
                              ),
                            if (_currentBodyData!.tdee != null)
                              _buildDataRow(
                                icon: Icons.trending_up,
                                label: 'TDEE (Gesamtumsatz)',
                                value: '${_currentBodyData!.tdee!.toStringAsFixed(0)} kcal/Tag',
                                color: Colors.deepOrange,
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Info-Card
                if (_currentBodyData != null)
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Deine Körperdaten werden für personalisierte Empfehlungen und automatische Kalorien-Schätzung verwendet.',
                              style: TextStyle(color: Colors.green.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
  
  Widget _buildDataRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

