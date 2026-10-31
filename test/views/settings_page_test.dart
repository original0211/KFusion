import 'dart:io';

import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/config/dns.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/config/network.dart';
import 'package:kfusion/views/developer.dart';
import 'package:kfusion/views/tools.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

ProviderContainer _container(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) {
  const size = Size(1400, 2400);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [profilesProvider.overrideWith(TestProfiles.new), ...overrides],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  return container;
}

Future<void> _pumpSettings(WidgetTester tester, ProviderContainer container) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const TestApp(child: ToolsView()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final home = Directory.systemTemp.createTempSync('settings-page-');
    await useAppPaths(home);
  });

  testWidgets('the settings page heads with the core switch card', (
    tester,
  ) async {
    final container = _container(tester);
    await _pumpSettings(tester, container);
    await tester.pump();

    expect(find.byType(CoreSwitchItem), findsOneWidget);
    expect(find.byType(CoreSwitchCard), findsOneWidget);
    for (final label in [
      'Auto launch',
      'Silent launch',
      'Auto run',
      'Minimize on exit',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final label in ['System proxy', 'TUN']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The index is flat: every destination is a row of this page,
    // the developer row included — no gate, no condition.
    for (final label in [
      'Language',
      'Theme',
      'Proxy settings',
      'Backup and restore',
      'General',
      'Network',
      'DNS',
      'On demand',
      'Logs',
      'Resources',
      'Developer mode',
      'Disclaimer',
      'About',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final label in ['Advanced', 'Advanced configuration']) {
      expect(find.text(label), findsNothing, reason: label);
    }
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('toggle rows flip their settings and carry no switch', (
    tester,
  ) async {
    final container = _container(tester);
    await _pumpSettings(tester, container);
    await tester.pump();

    expect(find.byType(Switch), findsNothing);

    final autoRun = container.read(appSettingProvider).autoRun;
    await tester.tap(find.text('Auto run'));
    await tester.pump();
    expect(container.read(appSettingProvider).autoRun, !autoRun);

    final systemProxy = container.read(networkSettingProvider).systemProxy;
    await tester.tap(find.text('System proxy'));
    await tester.pump();
    expect(container.read(networkSettingProvider).systemProxy, !systemProxy);
  });

  testWidgets('network and dns open straight from the index', (tester) async {
    final container = _container(tester);
    await _pumpSettings(tester, container);
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Network'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    expect(find.byType(NetworkListView), findsOneWidget);
  });

  testWidgets('the developer row stands on the index with no condition', (
    tester,
  ) async {
    final container = _container(tester);
    await _pumpSettings(tester, container);
    await tester.pump();

    expect(container.read(appSettingProvider).developerMode, isFalse);
    await tester.scrollUntilVisible(
      find.text('Developer mode'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Developer mode'));
    await tester.pumpAndSettle();
    expect(find.byType(DeveloperView), findsOneWidget);
  });

  testWidgets('search narrows the index and clearing restores it', (
    tester,
  ) async {
    final container = _container(tester);
    await _pumpSettings(tester, container);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'dns');
    await tester.pump();
    expect(find.text('DNS'), findsOneWidget);
    for (final label in ['Theme', 'General', 'Network', 'Logs', 'About']) {
      expect(find.text(label), findsNothing, reason: label);
    }

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No data'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('a search result opens its page directly', (tester) async {
    final container = _container(tester);
    await _pumpSettings(tester, container);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'dns');
    await tester.pump();
    await tester.tap(find.text('DNS'));
    await tester.pumpAndSettle();
    expect(find.byType(DnsView), findsOneWidget);
  });

  testWidgets('the general page keeps the rest, minus the migrated', (
    tester,
  ) async {
    final container = _container(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: GeneralView()),
      ),
    );
    await tester.pump();

    expect(find.byType(CoreSwitchItem), findsNothing);
    expect(find.text('Auto run'), findsNothing);
    expect(find.text('On demand'), findsOneWidget);
  });
}
