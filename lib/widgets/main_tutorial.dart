import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/services/tutorial_prefs.dart';

/// Spotlight coach-mark onboarding tour, shown once after a new user creates
/// their first nutrition goal. It highlights the four bottom-nav destinations
/// and the add-meal button so the four core areas of the app are discoverable.
///
/// Works identically for guest and logged-in users — completion state lives in
/// [TutorialPrefs] (device-local). The home screen owns the [GlobalKey]s for the
/// targets and drives both the auto-start (post goal creation) and the replay
/// path via [replayRequests].
class MainTutorial {
  MainTutorial._();

  /// Incremented whenever the user asks to replay the tour (e.g. from Profile).
  /// The home screen listens and restarts the tour once it is the active route.
  static final ValueNotifier<int> replayRequests = ValueNotifier<int>(0);

  /// Requests the tour be shown again. Safe to call from any screen; the home
  /// screen performs the actual presentation once it becomes active again.
  static void requestReplay() => replayRequests.value++;

  /// Builds and shows the coach-mark tour. The passed keys must be attached to
  /// the live bottom-nav icons and (optionally) the add-meal FAB. The tour is
  /// marked as seen as soon as it finishes or is skipped.
  static void show(
    BuildContext context, {
    required AppLocalizations l,
    required GlobalKey overviewTabKey,
    required GlobalKey foodTabKey,
    required GlobalKey activitiesTabKey,
    required GlobalKey reportsTabKey,
    GlobalKey? addFoodFabKey,
  }) {
    final targets = <TargetFocus>[
      _circleTarget('overview', overviewTabKey, ContentAlign.top,
          l.tutorialOverviewTitle, l.tutorialOverviewBody, l),
      _circleTarget('food', foodTabKey, ContentAlign.top, l.tutorialFoodTitle,
          l.tutorialFoodBody, l),
      _circleTarget('activities', activitiesTabKey, ContentAlign.top,
          l.tutorialActivitiesTitle, l.tutorialActivitiesBody, l),
      _circleTarget('reports', reportsTabKey, ContentAlign.top,
          l.tutorialReportsTitle, l.tutorialReportsBody, l),
    ];

    // The FAB only exists on some tabs; include it only if it is mounted so we
    // never spotlight an empty rectangle.
    if (addFoodFabKey?.currentContext != null) {
      targets.add(_circleTarget('add', addFoodFabKey!, ContentAlign.top,
          l.tutorialAddTitle, l.tutorialAddBody, l));
    }

    if (targets.isEmpty) return;

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.82,
      paddingFocus: 8,
      textSkip: l.tutorialSkip,
      alignSkip: Alignment.topRight,
      textStyleSkip:
          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      onFinish: TutorialPrefs.setSeenMainTutorial,
      onSkip: () {
        TutorialPrefs.setSeenMainTutorial();
        return true;
      },
    ).show(context: context);
  }

  static TargetFocus _circleTarget(
    String id,
    GlobalKey key,
    ContentAlign align,
    String title,
    String body,
    AppLocalizations l,
  ) {
    final isLast = id == 'add';
    return TargetFocus(
      identify: id,
      keyTarget: key,
      shape: ShapeLightFocus.Circle,
      radius: 8,
      enableOverlayTab: true,
      contents: [
        TargetContent(
          align: align,
          builder: (ctx, controller) =>
              _bubble(title, body, l, controller, isLast: isLast),
        ),
      ],
    );
  }

  static Widget _bubble(
    String title,
    String body,
    AppLocalizations l,
    TutorialCoachMarkController controller, {
    required bool isLast,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            // next() past the final target triggers the package's finish path,
            // which fires onFinish (marks the tour as seen).
            onPressed: () => controller.next(),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              isLast ? l.tutorialDone : l.tutorialNext,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
