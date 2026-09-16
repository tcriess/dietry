import 'package:flutter/material.dart';

/// The only file that names a concrete colour; everywhere else reads roles off
/// `context.colors`. Light values are what the screens used before.

/// [base] for icons and text on the page, [container] for a tinted card with
/// [onContainer] text on it.
@immutable
class ColorRole {
  final Color base;
  final Color on;
  final Color container;
  final Color containerHigh; // a step up, for a chip on a card
  final Color onContainer;
  final Color border;
  final Color strong; // a darker cast of base, for text needing weight

  const ColorRole({
    required this.base,
    required this.on,
    required this.container,
    required this.containerHigh,
    required this.onContainer,
    required this.border,
    required this.strong,
  });

  static ColorRole lerp(ColorRole a, ColorRole b, double t) => ColorRole(
        base: Color.lerp(a.base, b.base, t)!,
        on: Color.lerp(a.on, b.on, t)!,
        container: Color.lerp(a.container, b.container, t)!,
        containerHigh: Color.lerp(a.containerHigh, b.containerHigh, t)!,
        onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        strong: Color.lerp(a.strong, b.strong, t)!,
      );
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final ColorRole success; // saved, met, under budget
  final ColorRole warning; // over budget, needs attention, estimates
  final ColorRole danger; // errors, deletion, over the limit
  final ColorRole info; // explanation boxes and hints
  final ColorRole highlight; // favourites, streaks, tips, the Pro badge
  final ColorRole accent; // quick actions, body measurements
  final ColorRole brand; // AI features, the calorie budget
  final ColorRole water; // water intake, liquid foods
  final ColorRole plum; // goal boxes

  final Color muted; // secondary text
  final Color subtle; // tertiary text and hints
  final Color faint; // disabled icons, empty states, an unset star
  final Color border; // borders and dividers

  // A neutral tinted fill.
  final Color neutralContainer;
  final Color neutralContainerHigh;
  final Color onNeutralContainer;

  // Drawn over a photo or a scrim, where the background is fixed.
  final Color overlay;
  final Color onOverlay;
  final Color shadow;

  final Color chartGrid;
  final Color chartTooltipText;

  // Chart series that are not macros.
  final Color chartIntake;
  final Color chartTarget;
  final Color chartWeight;
  final Color chartBodyFat;

  // Macros, shared by the day list, the overview and the reports charts.
  // Validated as a categorical set: adjacent pairs stay apart under CVD.
  final Color macroCalories;
  final Color macroProtein;
  final Color macroFat;
  final Color macroCarbs;

  // Activity categories, in the order ActivityType declares them.
  final List<Color> categories;

  const AppColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.highlight,
    required this.accent,
    required this.brand,
    required this.water,
    required this.plum,
    required this.muted,
    required this.subtle,
    required this.faint,
    required this.border,
    required this.neutralContainer,
    required this.neutralContainerHigh,
    required this.onNeutralContainer,
    required this.overlay,
    required this.onOverlay,
    required this.shadow,
    required this.chartGrid,
    required this.chartTooltipText,
    required this.chartIntake,
    required this.chartTarget,
    required this.chartWeight,
    required this.chartBodyFat,
    required this.macroCalories,
    required this.macroProtein,
    required this.macroFat,
    required this.macroCarbs,
    required this.categories,
  });

  static const light = AppColors(
    success: ColorRole(
      base: Colors.green,
      on: Colors.white,
      container: Color(0xFFE8F5E9), // green.shade50
      containerHigh: Color(0xFFC8E6C9), // green.shade100
      onContainer: Color(0xFF1B5E20), // green.shade900
      border: Color(0xFFC8E6C9), // green.shade100
      strong: Color(0xFF388E3C), // green.shade700
    ),
    warning: ColorRole(
      base: Colors.orange,
      on: Colors.white,
      container: Color(0xFFFFF3E0), // orange.shade50
      containerHigh: Color(0xFFFFE0B2), // orange.shade100
      onContainer: Color(0xFFE65100), // orange.shade900
      border: Color(0xFFFFCC80), // orange.shade200
      strong: Color(0xFFF57C00), // orange.shade700
    ),
    danger: ColorRole(
      base: Colors.red,
      on: Colors.white,
      container: Color(0xFFFFCDD2), // red.shade100
      containerHigh: Color(0xFFFFCDD2), // red.shade100
      onContainer: Color(0xFFB71C1C), // red.shade900
      border: Color(0xFFEF9A9A), // red.shade200
      strong: Color(0xFFD32F2F), // red.shade700
    ),
    info: ColorRole(
      base: Colors.blue,
      on: Colors.white,
      container: Color(0xFFE3F2FD), // blue.shade50
      containerHigh: Color(0xFFBBDEFB), // blue.shade100
      onContainer: Color(0xFF0D47A1), // blue.shade900
      border: Color(0xFF90CAF9), // blue.shade200
      strong: Color(0xFF1976D2), // blue.shade700
    ),
    highlight: ColorRole(
      base: Colors.amber,
      on: Colors.black,
      container: Color(0xFFFFF8E1), // amber.shade50
      containerHigh: Color(0xFFFFECB3), // amber.shade100
      onContainer: Color(0xFFFF6F00), // amber.shade900
      border: Color(0xFFFFD54F), // amber.shade300
      strong: Color(0xFFFF8F00), // amber.shade800
    ),
    accent: ColorRole(
      base: Colors.teal,
      on: Colors.white,
      container: Color(0xFFE0F2F1), // teal.shade50
      containerHigh: Color(0xFFB2DFDB), // teal.shade100
      onContainer: Color(0xFF004D40), // teal.shade900
      border: Color(0xFF80CBC4), // teal.shade200
      strong: Color(0xFF00796B), // teal.shade700
    ),
    brand: ColorRole(
      base: Colors.deepPurple,
      on: Colors.white,
      container: Color(0xFFEDE7F6), // deepPurple.shade50
      containerHigh: Color(0xFFD1C4E9), // deepPurple.shade100
      onContainer: Color(0xFF311B92), // deepPurple.shade900
      border: Color(0xFFB39DDB), // deepPurple.shade200
      strong: Color(0xFF512DA8), // deepPurple.shade700
    ),
    water: ColorRole(
      base: Colors.lightBlue,
      on: Colors.white,
      container: Color(0xFFE1F5FE), // lightBlue.shade50
      containerHigh: Color(0xFFB3E5FC), // lightBlue.shade100
      onContainer: Color(0xFF01579B), // lightBlue.shade900
      border: Color(0xFF81D4FA), // lightBlue.shade200
      strong: Color(0xFF0288D1), // lightBlue.shade700
    ),
    plum: ColorRole(
      base: Colors.purple,
      on: Colors.white,
      container: Color(0xFFF3E5F5), // purple.shade50
      containerHigh: Color(0xFFE1BEE7), // purple.shade100
      onContainer: Color(0xFF4A148C), // purple.shade900
      border: Color(0xFFCE93D8), // purple.shade200
      strong: Color(0xFF7B1FA2), // purple.shade700
    ),
    muted: Color(0xFF757575), // grey.shade600
    subtle: Color(0xFF9E9E9E), // grey.shade500
    faint: Color(0xFFBDBDBD), // grey.shade400
    border: Color(0xFFE0E0E0), // grey.shade300
    neutralContainer: Color(0xFFF5F5F5), // grey.shade100
    neutralContainerHigh: Color(0xFFEEEEEE), // grey.shade200
    onNeutralContainer: Color(0xFF616161), // grey.shade700
    overlay: Colors.black,
    onOverlay: Colors.white,
    shadow: Colors.black26,
    chartGrid: Color(0xFFEEEEEE), // grey.shade200
    chartTooltipText: Colors.white,
    chartIntake: Colors.blue,
    chartTarget: Colors.red,
    chartWeight: Colors.deepOrange,
    chartBodyFat: Color(0xFFBA68C8), // purple.shade300
    macroCalories: Colors.deepPurple,
    macroProtein: Color(0xFFD32F2F), // red.shade700
    macroFat: Color(0xFFF57C00), // orange.shade700
    macroCarbs: Color(0xFF00897B), // teal.shade600
    categories: [
      Colors.green,
      Colors.blue,
      Colors.cyan,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.pink,
      Colors.grey,
    ],
  );

  // Accents lighten to carry on a dark surface; containers become a deep tint.
  static const dark = AppColors(
    success: ColorRole(
      base: Color(0xFF81C784), // green.shade300
      on: Colors.black,
      container: Color(0xFF1B3A22),
      containerHigh: Color(0xFF25502F),
      onContainer: Color(0xFFC8E6C9), // green.shade100
      border: Color(0xFF2E5C38),
      strong: Color(0xFFA5D6A7),
    ),
    warning: ColorRole(
      base: Color(0xFFFFB74D), // orange.shade300
      on: Colors.black,
      container: Color(0xFF3E2A10),
      containerHigh: Color(0xFF523818),
      onContainer: Color(0xFFFFE0B2), // orange.shade100
      border: Color(0xFF6B4A1C),
      strong: Color(0xFFFFCC80),
    ),
    danger: ColorRole(
      base: Color(0xFFE57373), // red.shade300
      on: Colors.black,
      container: Color(0xFF3E1D1B),
      containerHigh: Color(0xFF522825),
      onContainer: Color(0xFFFFCDD2), // red.shade100
      border: Color(0xFF6B322E),
      strong: Color(0xFFEF9A9A),
    ),
    info: ColorRole(
      base: Color(0xFF64B5F6), // blue.shade300
      on: Colors.black,
      container: Color(0xFF14293F),
      containerHigh: Color(0xFF1D3A55),
      onContainer: Color(0xFFBBDEFB), // blue.shade100
      border: Color(0xFF2A4C6E),
      strong: Color(0xFF90CAF9),
    ),
    highlight: ColorRole(
      base: Color(0xFFFFD54F), // amber.shade300
      on: Colors.black,
      container: Color(0xFF3B2F0B),
      containerHigh: Color(0xFF524012),
      onContainer: Color(0xFFFFECB3), // amber.shade100
      border: Color(0xFF6B5518),
      strong: Color(0xFFFFE082),
    ),
    accent: ColorRole(
      base: Color(0xFF4DB6AC), // teal.shade300
      on: Colors.black,
      container: Color(0xFF0C2F2B),
      containerHigh: Color(0xFF14403A),
      onContainer: Color(0xFFB2DFDB), // teal.shade100
      border: Color(0xFF1C544D),
      strong: Color(0xFF80CBC4),
    ),
    brand: ColorRole(
      base: Color(0xFFB39DDB), // deepPurple.shade200
      on: Colors.black,
      container: Color(0xFF2A2140),
      containerHigh: Color(0xFF382C55),
      onContainer: Color(0xFFD1C4E9), // deepPurple.shade100
      border: Color(0xFF4A3B6B),
      strong: Color(0xFFB39DDB),
    ),
    water: ColorRole(
      base: Color(0xFF4FC3F7), // lightBlue.shade300
      on: Colors.black,
      container: Color(0xFF0B2C3D),
      containerHigh: Color(0xFF123E54),
      onContainer: Color(0xFFB3E5FC), // lightBlue.shade100
      border: Color(0xFF1B506B),
      strong: Color(0xFF81D4FA),
    ),
    plum: ColorRole(
      base: Color(0xFFBA68C8), // purple.shade300
      on: Colors.black,
      container: Color(0xFF2E1533),
      containerHigh: Color(0xFF401E47),
      onContainer: Color(0xFFE1BEE7), // purple.shade100
      border: Color(0xFF55295C),
      strong: Color(0xFFCE93D8),
    ),
    muted: Color(0xFFC5C0C9),
    subtle: Color(0xFFA9A3B0),
    faint: Color(0xFF8B8593),
    border: Color(0xFF49454F),
    neutralContainer: Color(0xFF2B292F),
    neutralContainerHigh: Color(0xFF36343B),
    onNeutralContainer: Color(0xFFE6E0E9),
    overlay: Colors.black,
    onOverlay: Colors.white,
    shadow: Colors.black54,
    chartGrid: Color(0xFF3A373F),
    chartTooltipText: Colors.white,
    chartIntake: Color(0xFF64B5F6), // blue.shade300
    chartTarget: Color(0xFFE57373), // red.shade300
    chartWeight: Color(0xFFFF8A65), // deepOrange.shade300
    chartBodyFat: Color(0xFFCE93D8), // purple.shade200
    macroCalories: Color(0xFF7E57C2), // deepPurple.shade400
    macroProtein: Color(0xFFE53935), // red.shade600
    macroFat: Color(0xFFFB8C00), // orange.shade600
    macroCarbs: Color(0xFF26A69A), // teal.shade400
    categories: [
      Color(0xFF81C784), // green.shade300
      Color(0xFF64B5F6), // blue.shade300
      Color(0xFF4DD0E1), // cyan.shade300
      Color(0xFFFFB74D), // orange.shade300
      Color(0xFFE57373), // red.shade300
      Color(0xFFBA68C8), // purple.shade300
      Color(0xFFF06292), // pink.shade300
      Color(0xFFA9A3B0),
    ],
  );

  @override
  AppColors copyWith({
    ColorRole? success,
    ColorRole? warning,
    ColorRole? danger,
    ColorRole? info,
    ColorRole? highlight,
    ColorRole? accent,
    ColorRole? brand,
    ColorRole? water,
    ColorRole? plum,
    Color? muted,
    Color? subtle,
    Color? faint,
    Color? border,
    Color? neutralContainer,
    Color? neutralContainerHigh,
    Color? onNeutralContainer,
    Color? overlay,
    Color? onOverlay,
    Color? shadow,
    Color? chartGrid,
    Color? chartTooltipText,
    Color? chartIntake,
    Color? chartTarget,
    Color? chartWeight,
    Color? chartBodyFat,
    Color? macroCalories,
    Color? macroProtein,
    Color? macroFat,
    Color? macroCarbs,
    List<Color>? categories,
  }) =>
      AppColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        info: info ?? this.info,
        highlight: highlight ?? this.highlight,
        accent: accent ?? this.accent,
        brand: brand ?? this.brand,
        water: water ?? this.water,
        plum: plum ?? this.plum,
        muted: muted ?? this.muted,
        subtle: subtle ?? this.subtle,
        faint: faint ?? this.faint,
        border: border ?? this.border,
        neutralContainer: neutralContainer ?? this.neutralContainer,
        neutralContainerHigh: neutralContainerHigh ?? this.neutralContainerHigh,
        onNeutralContainer: onNeutralContainer ?? this.onNeutralContainer,
        overlay: overlay ?? this.overlay,
        onOverlay: onOverlay ?? this.onOverlay,
        shadow: shadow ?? this.shadow,
        chartGrid: chartGrid ?? this.chartGrid,
        chartTooltipText: chartTooltipText ?? this.chartTooltipText,
        chartIntake: chartIntake ?? this.chartIntake,
        chartTarget: chartTarget ?? this.chartTarget,
        chartWeight: chartWeight ?? this.chartWeight,
        chartBodyFat: chartBodyFat ?? this.chartBodyFat,
        macroCalories: macroCalories ?? this.macroCalories,
        macroProtein: macroProtein ?? this.macroProtein,
        macroFat: macroFat ?? this.macroFat,
        macroCarbs: macroCarbs ?? this.macroCarbs,
        categories: categories ?? this.categories,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    List<Color> lerpList(List<Color> a, List<Color> b) => [
          for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
        ];
    return AppColors(
      success: ColorRole.lerp(success, other.success, t),
      warning: ColorRole.lerp(warning, other.warning, t),
      danger: ColorRole.lerp(danger, other.danger, t),
      info: ColorRole.lerp(info, other.info, t),
      highlight: ColorRole.lerp(highlight, other.highlight, t),
      accent: ColorRole.lerp(accent, other.accent, t),
      brand: ColorRole.lerp(brand, other.brand, t),
      water: ColorRole.lerp(water, other.water, t),
      plum: ColorRole.lerp(plum, other.plum, t),
      muted: Color.lerp(muted, other.muted, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      border: Color.lerp(border, other.border, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
      neutralContainerHigh:
          Color.lerp(neutralContainerHigh, other.neutralContainerHigh, t)!,
      onNeutralContainer:
          Color.lerp(onNeutralContainer, other.onNeutralContainer, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      onOverlay: Color.lerp(onOverlay, other.onOverlay, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      chartTooltipText:
          Color.lerp(chartTooltipText, other.chartTooltipText, t)!,
      chartIntake: Color.lerp(chartIntake, other.chartIntake, t)!,
      chartTarget: Color.lerp(chartTarget, other.chartTarget, t)!,
      chartWeight: Color.lerp(chartWeight, other.chartWeight, t)!,
      chartBodyFat: Color.lerp(chartBodyFat, other.chartBodyFat, t)!,
      macroCalories: Color.lerp(macroCalories, other.macroCalories, t)!,
      macroProtein: Color.lerp(macroProtein, other.macroProtein, t)!,
      macroFat: Color.lerp(macroFat, other.macroFat, t)!,
      macroCarbs: Color.lerp(macroCarbs, other.macroCarbs, t)!,
      categories: lerpList(categories, other.categories),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;

  ColorScheme get scheme => Theme.of(this).colorScheme;
}
