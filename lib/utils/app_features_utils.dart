import 'package:flutter/material.dart';
import '../app_features.dart';
import '../services/app_logger.dart';

/// Utility functions for feature gating and premium tier prompts.
///
/// **Purpose**: Simplifies common patterns when using [AppFeatures] in screens.
///
/// **Example**:
/// ```dart
/// if (AppFeaturesUtils.requirePro('meal_planning')) {
///   return AppFeaturesUtils.buildUpgradePrompt(context, feature: 'Meal Planning');
/// }
/// ```
class AppFeaturesUtils {
  AppFeaturesUtils._();

  /// Returns true if a feature is **not** available and user is not pro.
  /// Useful for gating screens behind upgrade checks.
  ///
  /// ```dart
  /// if (AppFeaturesUtils.requirePro('mealTemplates')) {
  ///   return upgradePrompt;
  /// }
  /// ```
  static bool requirePro(String featureName) {
    final available = _isFeatureAvailable(featureName);
    return !available || (available && !AppFeatures.isPro && _isPremiumFeature(featureName));
  }

  /// Checks if a feature is available for the current user/edition.
  static bool isFeatureAvailable(String featureName) {
    return _isFeatureAvailable(featureName);
  }

  /// Checks if a feature is cloud-only (not in Community Edition).
  static bool isCloudOnly(String featureName) {
    return ['meal_templates', 'micronutrients', 'activity_quick_add', 'streaks', 'reports_export', 'advanced_analytics', 'multiple_profiles']
        .contains(featureName);
  }

  /// Checks if a feature requires Pro tier.
  static bool requiresProTier(String featureName) {
    return ['advanced_analytics', 'multiple_profiles'].contains(featureName);
  }

  /// Builds a standard upgrade prompt widget.
  ///
  /// Shows a card with feature name, description, and upgrade button.
  static Widget buildUpgradePrompt(
    BuildContext context, {
    required String feature,
    String? description,
    VoidCallback? onUpgrade,
  }) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                feature,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onUpgrade,
                child: const Text('Upgrade to Pro'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Logs current feature availability (debug).
  static void debugLogFeatures() {
    appLogger.d('=== AppFeatures Debug ===');
    final isCloud = AppFeatures.role != 'community';
    appLogger.d('Edition: ${isCloud ? "Cloud" : "Community"}');
    appLogger.d('Role: ${AppFeatures.role}');
    appLogger.d('Is Pro: ${AppFeatures.isPro}');
    appLogger.d('');
    appLogger.d('Features:');
    appLogger.d('  Meal Templates: ${AppFeatures.mealTemplates}');
    appLogger.d('  Micro Nutrients: ${AppFeatures.microNutrients}');
    appLogger.d('  Activity Quick Add: ${AppFeatures.activityQuickAdd}');
    appLogger.d('  Streaks: ${AppFeatures.streaks}');
    appLogger.d('  Reports Export: ${AppFeatures.reportsExport}');
    appLogger.d('  Advanced Analytics: ${AppFeatures.advancedAnalytics}');
    appLogger.d('  Multiple Profiles: ${AppFeatures.multipleProfiles}');
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static bool _isFeatureAvailable(String featureName) {
    switch (featureName) {
      case 'meal_templates':
        return AppFeatures.mealTemplates;
      case 'micronutrients':
        return AppFeatures.microNutrients;
      case 'activity_quick_add':
        return AppFeatures.activityQuickAdd;
      case 'streaks':
        return AppFeatures.streaks;
      case 'reports_export':
        return AppFeatures.reportsExport;
      case 'advanced_analytics':
        return AppFeatures.advancedAnalytics;
      case 'multiple_profiles':
        return AppFeatures.multipleProfiles;
      default:
        return false;
    }
  }

  static bool _isPremiumFeature(String featureName) {
    // Features that cost money (need upgrade prompt)
    return requiresProTier(featureName) || featureName == 'meal_templates' || featureName == 'micronutrients' || featureName == 'activity_quick_add';
  }
}
