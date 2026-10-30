import 'dart:io';

import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/network.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

ProviderContainer _container(
  WidgetTester tester, {
  Size size = const Size(400, 844),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [profilesProvider.overrideWith(() => TestProfiles(const []))],
  );
  addTearDown(container.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final home = Directory.systemTemp.createTempSync('cabin3-standards-');
    await useAppPaths(home);
  });

  group('network sample page (cabin batch 3, #19)', () {
    Future<void> pumpNetwork(WidgetTester tester) async {
      final container = _container(tester, size: const Size(400, 1760));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: Scaffold(body: NetworkListView())),
        ),
      );
      await tester.pump();
    }

    testWidgets('sections are headed hara sections of hairline rows', (
      tester,
    ) async {
      await pumpNetwork(tester);
      for (final title in ['System', 'Options', 'TUN', 'Outbound']) {
        expect(find.text(title), findsWidgets);
      }
      expect(find.byType(HaraHairline), findsWidgets);
    });

    testWidgets('section rows rest on the hara hairline', (tester) async {
      await pumpNetwork(tester);
      final context = tester.element(find.byType(HaraHairline).first);
      final line = tester.widget<HaraHairline>(find.byType(HaraHairline).first);
      expect(line.color, context.haraPalette.line);
    });

    testWidgets('number rows surface their value under the label', (
      tester,
    ) async {
      await pumpNetwork(tester);
      expect(find.text('15 seconds'), findsOneWidget);
      expect(find.text('30 seconds'), findsOneWidget);
    });
  });
}
