import 'dart:io';

import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/form_row.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/views/config/rules.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/network.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database_providers.dart';
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

    testWidgets('sections are headed panels of shared family rows', (
      tester,
    ) async {
      await pumpNetwork(tester);
      final headers = tester
          .widgetList<ListHeader>(find.byType(ListHeader))
          .map((header) => header.title)
          .toList();
      expect(headers, containsAll(['System', 'Options', 'TUN', 'Outbound']));
      expect(find.byType(DecorationListItem), findsWidgets);
      expect(find.byType(FormRow), findsWidgets);
    });

    testWidgets('section rows carry the cabin rim at rest', (tester) async {
      await pumpNetwork(tester);
      final context = tester.element(find.byType(DecorationListItem).first);
      final scheme = Theme.of(context).colorScheme;
      final button = tester.widget<FilledButton>(
        find
            .descendant(
              of: find.byType(DecorationListItem).first,
              matching: find.byType(FilledButton),
            )
            .first,
      );
      final side = button.style?.side?.resolve(const <WidgetState>{});
      expect(side?.color, scheme.cabinRim);
    });

    testWidgets('number rows surface their value as the subtitle', (
      tester,
    ) async {
      await pumpNetwork(tester);
      final subtitled = tester
          .widgetList<ListItem>(find.byType(ListItem))
          .where((item) => item.subtitle != null)
          .length;
      expect(subtitled, greaterThanOrEqualTo(2));
    });
  });

  group('added rules target colors (cabin batch 3, #24)', () {
    testWidgets('direct reads success, reject warning, unknown target error', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          globalRulesProvider.overrideWith(
            () => TestGlobalRules(const [
              Rule(
                id: 1,
                ruleAction: RuleAction.DOMAIN_SUFFIX,
                content: 'example.com',
                ruleTarget: 'DIRECT',
                order: '1',
              ),
              Rule(
                id: 2,
                ruleAction: RuleAction.IP_CIDR,
                content: '203.0.113.0/24',
                ruleTarget: 'REJECT',
                order: '2',
              ),
              Rule(
                id: 3,
                ruleAction: RuleAction.GEOIP,
                content: 'CN',
                ruleTarget: 'no-such-policy',
                order: '3',
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
      globalState.container = container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: AddedRulesView()),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(AddedRulesView));
      final scheme = Theme.of(context).colorScheme;
      Color? targetColor(String target) =>
          tester.widget<Text>(find.text(target)).style?.color;
      expect(targetColor('DIRECT'), scheme.success);
      expect(targetColor('REJECT'), scheme.warning);
      expect(targetColor('no-such-policy'), scheme.error);
    });
  });
}
