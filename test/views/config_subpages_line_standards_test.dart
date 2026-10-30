import 'dart:io';

import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/form_row.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/dns.dart';
import 'package:kfusion/views/config/network.dart';
import 'package:kfusion/views/config/on_demand.dart';
import 'package:kfusion/widgets/config_item.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wifi_ssid/wifi_ssid.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _TestExcludeSSIDs extends ExcludeSSIDs {
  @override
  List<String> build() => const [];
}

class _TestLocationPermissions extends LocationPermissions {
  @override
  WifiSsidPermission build() => WifiSsidPermission.granted;
}

class _TestBatteryOptimizationIgnored extends BatteryOptimizationIgnored {
  @override
  Stream<bool> build() => Stream.value(true);

  @override
  Future<void> request() async {}
}

ProviderContainer _container(
  WidgetTester tester,
  List<Override> overrides, {
  Size size = const Size(400, 844),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(
        () => TestProfiles([
          const Profile(
            id: 1,
            type: ProfileType.custom,
            autoUpdateDuration: Duration.zero,
          ),
        ]),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  return container;
}

ColorScheme _schemeOf(WidgetTester tester, Finder finder) {
  return Theme.of(tester.element(finder)).colorScheme;
}

void main() {
  setUpAll(() async {
    final home = Directory.systemTemp.createTempSync('pc5-standards-');
    await useAppPaths(home);
  });

  group('override subpages', () {
    testWidgets('the dns empty state is the standard status with the dns '
        'illustration, not the brand mark', (tester) async {
      final container = _container(tester, []);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: DnsView()),
        ),
      );
      await tester.pump();
      final status = tester.widget<NullStatus>(find.byType(NullStatus));
      expect(status.brandMark, isFalse);
      expect(status.illustration, NullStatusIllustration.dns);
      expect(find.byType(EmptyIllustration), findsOneWidget);
      expect(find.text('Add override entry'), findsOneWidget);
    });

    testWidgets('filled dns entries render as config family rows', (
      tester,
    ) async {
      final container = _container(tester, []);
      container
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) => state.copyWith(
              dnsOverrideKeys: {
                DnsOverrideKey.ipv6,
                DnsOverrideKey.enhancedMode,
                DnsOverrideKey.nameserver,
              },
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: DnsView()),
        ),
      );
      await tester.pump();
      expect(find.byType(ConfigToggleItem), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is ConfigOptionsItem),
        findsOneWidget,
      );
      expect(find.byType(ConfigListEditItem), findsOneWidget);
      expect(find.byType(EntryButton), findsNWidgets(3));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('network sample page', () {
    testWidgets('the tun add row keeps the shared primary add form', (
      tester,
    ) async {
      final container = _container(tester, []);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: Scaffold(body: NetworkListView())),
        ),
      );
      await tester.pump();
      final addRow = find.byWidgetPredicate(
        (widget) => widget is FormRow && widget.key == const ValueKey(#add),
      );
      expect(addRow, findsOneWidget);
      final row = tester.widget<FormRow>(addRow);
      expect(row.titleStyle?.color, _schemeOf(tester, addRow).primary);
      expect(
        find.descendant(of: addRow, matching: find.byType(EntryButton)),
        findsOneWidget,
      );
    });
  });

  group('on demand', () {
    testWidgets(
      'the ssid empty state is the standard wifi status, not the brand mark',
      (tester) async {
        final container = _container(tester, [
          excludeSSIDsProvider.overrideWith(_TestExcludeSSIDs.new),
          locationPermissionsProvider.overrideWith(
            _TestLocationPermissions.new,
          ),
          batteryOptimizationIgnoredProvider.overrideWith(
            _TestBatteryOptimizationIgnored.new,
          ),
          isStartProvider.overrideWithValue(false),
        ]);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(
              child: OnDemandView(isAndroid: true, isMacOS: false),
            ),
          ),
        );
        await tester.pump();
        final status = tester.widget<NullStatus>(find.byType(NullStatus));
        expect(status.brandMark, isFalse);
        expect(status.illustration, NullStatusIllustration.wifi);
      },
    );
  });
}
