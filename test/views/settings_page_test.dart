import 'dart:io';

import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/advanced_gate.dart';
import 'package:kfusion/views/config/advanced.dart';
import 'package:kfusion/views/config/general.dart';
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
    for (final label in [
      'Language',
      'Theme',
      'Backup and restore',
      'Hotkey management',
      'Advanced',
      'Disclaimer',
      'About',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The gated pages have no direct row on the daily surface.
    for (final label in [
      'Advanced configuration',
      'General',
      'Custom profile resources',
      'Proxy settings',
      'Resources',
      'Logs',
      'Font family',
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }
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

  testWidgets('the advanced gate gathers the gated pages behind one door', (
    tester,
  ) async {
    final container = _container(tester);
    await _pumpSettings(tester, container);
    await tester.pump();

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byType(AdvancedGateView), findsOneWidget);
    for (final label in [
      'Advanced configuration',
      'General',
      'Custom profile resources',
      'Proxy settings',
      'Resources',
      'Logs',
      'Font family',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Developer mode'), findsNothing);

    await tester.tap(find.text('Advanced configuration'));
    await tester.pumpAndSettle();
    expect(find.byType(AdvancedConfigView), findsOneWidget);
    for (final label in ['Network', 'DNS', 'Added rules']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the developer row keeps its condition inside the gate', (
    tester,
  ) async {
    final container = _container(tester);
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(developerMode: true));
    await _pumpSettings(tester, container);
    await tester.pump();

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Developer mode'), findsOneWidget);
  });

  testWidgets('the gated general page keeps the rest, minus the migrated', (
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
