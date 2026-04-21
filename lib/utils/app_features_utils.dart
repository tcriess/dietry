import 'package:flutter/material.dart';
import 'package:dietry_cloud/dietry_cloud.dart' show premiumFeatures;
import '../app_config.dart';
import '../app_features.dart';
import '../services/app_logger.dart';

/// Utility functions for feature gating and premium tier prompts.
class AppFeaturesUtils {
  AppFeaturesUtils._();

  /// Returns true if a feature is not available to the current user.
  static bool requiresPro(String featureName) {
    return !_isFeatureAvailable(featureName);
  }

  /// Checks if a feature is available for the current user/edition.
  static bool isFeatureAvailable(String featureName) {
    return _isFeatureAvailable(featureName);
  }

  /// Checks if a feature is cloud-only (not in Community Edition).
  static bool isCloudOnly(String featureName) {
    return [
      'meal_templates',
      'micronutrients',
      'activity_quick_add',
      'streaks',
      'reports_export',
      'advanced_analytics',
    ].contains(featureName);
  }

  /// Checks if a feature requires Pro tier.
  static bool requiresProTier(String featureName) {
    return ['micronutrients', 'advanced_analytics'].contains(featureName);
  }

  /// Builds a standard upgrade prompt widget.
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
              if (AppConfig.isCloudEdition) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onUpgrade ??
                      () => premiumFeatures.showUpgradeSheet(
                            context: context,
                            featureName: feature,
                          ),
                  child: const Text('Upgrade to Pro'),
                ),
              ],
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
    appLogger.d('Is Paid: ${AppFeatures.isPaid}');
    appLogger.d('');
    appLogger.d('Features:');
    appLogger.d('  Meal Templates: ${AppFeatures.mealTemplates}');
    appLogger.d('  Micro Nutrients: ${AppFeatures.microNutrients}');
    appLogger.d('  Activity Quick Add: ${AppFeatures.activityQuickAdd}');
    appLogger.d('  Streaks: ${AppFeatures.streaks}');
    appLogger.d('  Reports Export: ${AppFeatures.reportsExport}');
    appLogger.d('  Advanced Analytics: ${AppFeatures.advancedAnalytics}');
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
      default:
        return false;
    }
  }
}
