import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/screens/settings_screen.dart';
import 'package:simsync/settings/app_settings_controller.dart';
import 'package:simsync/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'navigation selection switches atomically with no lingering highlight',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AppSettingsController(
        defaultLocalNotePath: '/tmp/default-notes',
      );
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColorsExtension.light]),
          home: Scaffold(body: SettingsScreen(settingsController: controller)),
        ),
      );
      await tester.pumpAndSettle();

      Color navBackground(String label) {
        final inkwell = find
            .ancestor(
              of: find.text(label),
              matching: find.byType(InkWell),
            )
            .first;
        final container = find
            .descendant(of: inkwell, matching: find.byType(Container))
            .first;
        final decoration =
            tester.widget<Container>(container).decoration! as BoxDecoration;
        return decoration.color!;
      }

      // Storage starts selected (highlighted), Sync is not.
      final selectedColor = navBackground('Storage');
      expect(selectedColor, isNot(Colors.transparent));
      expect(navBackground('Sync'), Colors.transparent);

      // Click Sync, then advance only a single mid-animation frame.
      await tester.ensureVisible(find.text('Sync'));
      await tester.tap(find.text('Sync'));
      await tester.pump(const Duration(milliseconds: 16));

      // The previously-selected Storage item must be FULLY deselected already
      // (no fading highlight blend), and Sync fully selected — proving the
      // selection state changes atomically rather than animating.
      expect(navBackground('Storage'), Colors.transparent);
      expect(navBackground('Sync'), selectedColor);

      // The selected indicator bar likewise moved.
      expect(
        find.byKey(const ValueKey('settings-nav-selected-storage')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-nav-selected-sync')),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
    },
  );
}
