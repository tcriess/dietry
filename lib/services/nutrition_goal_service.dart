// Nutrition Goal Service für CRUD-Operationen
import '../models/models.dart';
import 'neon_database_service.dart';
import 'user_profile_service.dart';
import 'user_body_measurements_service.dart';
import 'nutrition_calculator.dart';

class NutritionGoalService {
  final NeonDatabaseService _db;
  
  NutritionGoalService(this._db);
  
  /// Hole die User-ID aus dem DB-Service
  String? get _userId => _db.userId;
  
  /// Hole das aktuelle Nutrition Goal (basierend auf valid_from)
  Future<NutritionGoal?> getCurrentGoal() async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig - kann Goal nicht laden');
        return null;
      }
      
      final userId = _userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar - kann Goal nicht laden');
        return null;
      }
      
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      final response = await _db.client
        .from('nutrition_goals')
        .select()
        .eq('user_id', userId)
        .lte('valid_from', today)
        .order('valid_from', ascending: false)
        .limit(1)
        .maybeSingle();
      
      if (response == null) return null;
      
      return NutritionGoal.fromJson(response);
    } catch (e) {
      print('❌ Fehler beim Abrufen des aktuellen Goals: $e');
      return null;
    }
  }
  
  /// Hole das Nutrition Goal für ein bestimmtes Datum
  /// 
  /// Findet das Goal mit dem neuesten valid_from <= targetDate
  Future<NutritionGoal?> getGoalForDate(DateTime date) async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig - kann Goal nicht laden');
        return null;
      }
      
      final userId = _userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar - kann Goal nicht laden');
        return null;
      }
      
      // Konvertiere Datum zu String (YYYY-MM-DD)
      final dateString = date.toIso8601String().split('T')[0];
      
      final response = await _db.client
        .from('nutrition_goals')
        .select()
        .eq('user_id', userId)
        .lte('valid_from', dateString)
        .order('valid_from', ascending: false)
        .limit(1)
        .maybeSingle();
      
      if (response == null) return null;
      
      return NutritionGoal.fromJson(response);
    } catch (e) {
      print('❌ Fehler beim Abrufen des Goals für ${date.toIso8601String().split('T')[0]}: $e');
      return null;
    }
  }
  
  /// Prüft ob ein Goal für ein bestimmtes Datum existiert
  /// 
  /// Returns true wenn mindestens ein Goal mit valid_from <= targetDate existiert
  Future<bool> hasGoalForDate(DateTime date) async {
    final goal = await getGoalForDate(date);
    return goal != null;
  }
  
  /// Erstelle oder aktualisiere ein Nutrition Goal
  Future<NutritionGoal> createOrUpdateGoal(NutritionGoal goal, {DateTime? validFrom}) async {
    try {
      print('🔍 createOrUpdateGoal() aufgerufen...');
      
      // ✅ Stelle sicher dass Token gültig ist BEVOR wir irgendetwas tun
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig - kann Goal nicht erstellen');
      }
      
      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar - kann Goal nicht erstellen');
      }
      
      final validFromDate = (validFrom ?? DateTime.now()).toIso8601String().split('T')[0];
      
      print('   User-ID: $userId');
      print('   Datum (valid_from): $validFromDate');
      print('   Goal: ${goal.calories.toInt()} kcal, P${goal.protein.toInt()}g, F${goal.fat.toInt()}g, C${goal.carbs.toInt()}g');
      
      // Prüfe ob bereits ein Goal für diesen Tag existiert
      print('   Prüfe ob Goal für $validFromDate bereits existiert...');
      final existing = await _db.client
        .from('nutrition_goals')
        .select('id, calories')
        .eq('user_id', userId)
        .eq('valid_from', validFromDate)
        .maybeSingle();
      
      if (existing != null) {
        print('   ✅ Existierendes Goal gefunden:');
        print('      - ID: ${existing['id']}');
        print('      - Alte Kalorien: ${existing['calories']}');
        print('      - Neue Kalorien: ${goal.calories.toInt()}');
        print('      → Mache UPDATE (überschreibe existierendes Goal)');
      } else {
        print('   ℹ️ Kein existierendes Goal gefunden');
        print('      → Mache INSERT (neues Goal)');
      }
      
      final json = goal.toJson();
      json['user_id'] = userId;
      json['valid_from'] = validFromDate;
      
      // UPSERT ohne .select() (workaround für PostgREST Prefer-Header-Bug)
      // Hole das Ergebnis immer manuell nach dem UPSERT
      print('   Führe UPSERT aus...');
      await _db.client
        .from('nutrition_goals')
        .upsert(
          json,
          onConflict: 'user_id,valid_from',
        );

      print('✅ UPSERT erfolgreich');

      // Hole das Goal aus DB
      print('   Hole gespeichertes Goal aus DB...');
      final createdGoal = await _db.client
        .from('nutrition_goals')
        .select()
        .eq('user_id', userId)
        .eq('valid_from', validFromDate)
        .single();

      print('✅ Goal erfolgreich aus DB geladen (ID: ${createdGoal['id']})');
      return NutritionGoal.fromJson(createdGoal);
    } catch (e, stackTrace) {
      print('❌ Fehler beim UPSERT des Goals: $e');
      print('   Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  /// Berechnet das Ernährungsziel neu aus dem aktuellen Profil + aktueller Gewichtsmessung
  /// und speichert es für heute. Gibt null zurück wenn Profildaten unvollständig sind.
  /// Schlägt immer still fehl — darf die aufrufende Aktion nie blockieren.
  static Future<NutritionGoal?> autoAdjustGoal(NeonDatabaseService db) async {
    try {
      final service = NutritionGoalService(db);

      // Use the tracking method from the most recent stored goal (fallback: tdeeHybrid).
      final currentGoal = await service.getCurrentGoal();
      final method = currentGoal?.trackingMethod ?? TrackingMethod.tdeeHybrid;
      final preserveMacroOnly = currentGoal?.macroOnly ?? false;

      final profile = await UserProfileService(db).getCurrentProfile();
      final measurement = await UserBodyMeasurementsService(db).getCurrentMeasurement();

      if (profile == null || measurement == null) return null;
      final age = profile.age;
      if (age == null || profile.height == null || profile.gender == null ||
          profile.activityLevel == null || profile.weightGoal == null) return null;

      final bodyData = UserBodyData(
        weight: measurement.weight,
        height: profile.height!,
        gender: profile.gender!,
        age: age,
        activityLevel: profile.activityLevel!,
        weightGoal: profile.weightGoal!,
      );

      final recommendation = NutritionCalculator.calculateMacros(bodyData, method: method);
      final waterGoalMl = NutritionCalculator.calculateWaterGoal(measurement.weight);
      final baseGoal = NutritionCalculator.createGoalFromRecommendation(recommendation);
      final goal = NutritionGoal(
        calories: baseGoal.calories,
        protein: baseGoal.protein,
        fat: baseGoal.fat,
        carbs: baseGoal.carbs,
        trackingMethod: baseGoal.trackingMethod,
        waterGoalMl: waterGoalMl,
        macroOnly: preserveMacroOnly,
      );
      return await service.createOrUpdateGoal(goal);
    } catch (_) {
      return null;
    }
  }

  /// Datum des frühesten Nutrition Goals (= Beginn des Trackings).
  /// Gibt null zurück wenn noch kein Goal existiert.
  Future<DateTime?> getEarliestGoalDate() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return null;
      final userId = _userId;
      if (userId == null) return null;

      final response = await _db.client
        .from('nutrition_goals')
        .select('valid_from')
        .eq('user_id', userId)
        .order('valid_from', ascending: true)
        .limit(1)
        .maybeSingle();

      if (response == null) return null;
      return DateTime.parse(response['valid_from'] as String);
    } catch (e) {
      return null;
    }
  }

  /// Hole alle Goals des Users
  Future<List<NutritionGoal>> getAllGoals() async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig - kann Goals nicht laden');
        return [];
      }
      
      final userId = _userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar - kann Goals nicht laden');
        return [];
      }
      
      final response = await _db.client
        .from('nutrition_goals')
        .select()
        .eq('user_id', userId)
        .order('valid_from', ascending: false);
      
      return (response as List)
        .map((json) => NutritionGoal.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      print('❌ Fehler beim Abrufen aller Goals: $e');
      return [];
    }
  }
  
  /// Lösche ein Goal
  Future<void> deleteGoal(String id) async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig - kann Goal nicht löschen');
      }
      
      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar - kann Goal nicht löschen');
      }
      
      await _db.client
        .from('nutrition_goals')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);  // Sicherheit: Nur eigene Goals
    } catch (e) {
      print('❌ Fehler beim Löschen des Goals: $e');
      rethrow;
    }
  }
}
