import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dietry/services/tutorial_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TutorialPrefs', () {
    test('defaults to not-seen when no value is stored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await TutorialPrefs.hasSeenMainTutorial(), isFalse);
    });

    test('setSeenMainTutorial persists the flag', () async {
      SharedPreferences.setMockInitialValues({});
      await TutorialPrefs.setSeenMainTutorial();
      expect(await TutorialPrefs.hasSeenMainTutorial(), isTrue);
    });

    test('resetMainTutorial clears the flag (tour will show again)', () async {
      SharedPreferences.setMockInitialValues({'tutorial_main_seen': true});
      expect(await TutorialPrefs.hasSeenMainTutorial(), isTrue);
      await TutorialPrefs.resetMainTutorial();
      expect(await TutorialPrefs.hasSeenMainTutorial(), isFalse);
    });
  });
}
