import 'dart:async';

import 'package:kfusion/common/service_probe.dart' show routedOutbound;
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/ip_quality.dart';
import 'package:kfusion/providers/outbound_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/dashboard/hara_dashboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';

const _ip = '203.0.113.9';
const _node = 'Tokyo 01';

const _profile = Profile(
  id: 1,
  label: 'Home',
  autoUpdateDuration: Duration.zero,
);

const _residential = IpQuality(
  ip: _ip,
  source: IpQualitySource.ipLocate,
  type: IpType.residential,
  organization: 'Example Broadband',
  asn: 64500,
);

const _stamp = RouteStamp(
  coreEpoch: 1,
  picksVersion: 1,
  hostEpoch: 1,
  proxied: true,
  chains: [_node],
);

const _freshEntry = ProbeEntry<IpInfo>(
  phase: ProbePhase.fresh,
  value: IpInfo(ip: _ip, countryCode: 'GB'),
  stamp: _stamp,
);

const _japanEntry = ProbeEntry<IpInfo>(
  phase: ProbePhase.fresh,
  value: IpInfo(ip: _ip, countryCode: 'JP'),
  stamp: _stamp,
);

const _unlistedEntry = ProbeEntry<IpInfo>(
  phase: ProbePhase.fresh,
  value: IpInfo(ip: _ip, countryCode: 'AQ'),
  stamp: _stamp,
);

class _RecordingSetupAction extends SetupAction {
  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) {
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
    return Future.value(true);
  }
}

class _QualityStub {
  _QualityStub(this.answer);

  final Future<IpQuality> Function(String ip) answer;
  final calls = <String>[];

  Future<IpQuality> call(Ref ref, String ip) {
    calls.add(ip);
    return answer(ip);
  }
}

Widget _app({
  required ProbeEntry<IpInfo> entry,
  required _QualityStub quality,
  Locale locale = const Locale('en'),
}) {
  return TestApp(
    locale: locale,
    overrides: [
      profilesProvider.overrideWithValue(const [_profile]),
      currentProfileIdProvider.overrideWithBuild((_, _) => 1),
      suspendProvider.overrideWithValue(false),
      setupActionProvider.overrideWith(_RecordingSetupAction.new),
      outboundIpProbeProvider.overrideWithBuild(
        (_, _) => RoutedProbeState({routedOutbound: entry}),
      ),
      ipQualityProvider.overrideWith(quality.call),
    ],
    child: const HaraDashboard(),
  );
}

Future<void> _pumpConnected(WidgetTester tester, Widget app) async {
  // The test font draws every glyph a full em wide, so the appended type
  // needs a wider surface than the 412 dp the sibling suites use.
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.tap(find.byType(DiscRingMotif));
  await tester.pump();
  await tester.pump();
}

Finder _exitValue(String text, {String label = 'Exit'}) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
  matching: find.text(text),
);

void main() {
  setUp(() async {
    await mockPreferences();
  });

  testWidgets('the exit row shows country and type once quality lands', (
    tester,
  ) async {
    final quality = _QualityStub((_) async => _residential);
    await _pumpConnected(tester, _app(entry: _freshEntry, quality: quality));

    expect(_exitValue('$_ip · United Kingdom · Residential'), findsOneWidget);
    expect(quality.calls, [_ip]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the country lands with the IP while quality is pending', (
    tester,
  ) async {
    final pending = Completer<IpQuality>();
    addTearDown(() => pending.complete(_residential));
    final quality = _QualityStub((_) => pending.future);
    await _pumpConnected(tester, _app(entry: _freshEntry, quality: quality));

    expect(_exitValue('$_ip · United Kingdom'), findsOneWidget);
    expect(find.textContaining('Residential'), findsNothing);
    expect(quality.calls, [_ip]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed quality lookup keeps the country, drops the type', (
    tester,
  ) async {
    final quality = _QualityStub(
      (_) async => throw StateError('lookup failed'),
    );
    await _pumpConnected(tester, _app(entry: _freshEntry, quality: quality));

    expect(_exitValue('$_ip · United Kingdom'), findsOneWidget);
    expect(find.textContaining('Residential'), findsNothing);
    expect(quality.calls, [_ip]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unlisted country code drops the country segment', (
    tester,
  ) async {
    final quality = _QualityStub((_) async => _residential);
    await _pumpConnected(tester, _app(entry: _unlistedEntry, quality: quality));

    expect(_exitValue('$_ip · Residential'), findsOneWidget);
    expect(quality.calls, [_ip]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the country and type follow the app language', (tester) async {
    final quality = _QualityStub((_) async => _residential);
    await _pumpConnected(
      tester,
      _app(
        entry: _japanEntry,
        quality: quality,
        locale: const Locale('zh', 'CN'),
      ),
    );

    expect(_exitValue('$_ip · 日本 · 住宅', label: '出口'), findsOneWidget);
    expect(quality.calls, [_ip]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hide ip masks the row and skips the quality lookup', (
    tester,
  ) async {
    final quality = _QualityStub((_) async => _residential);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWithValue(const [_profile]),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        suspendProvider.overrideWithValue(false),
        setupActionProvider.overrideWith(_RecordingSetupAction.new),
        outboundIpProbeProvider.overrideWithBuild(
          (_, _) => const RoutedProbeState({routedOutbound: _freshEntry}),
        ),
        ipQualityProvider.overrideWith(quality.call),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(hideIp: true));
    await _pumpConnected(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(locale: Locale('en'), child: HaraDashboard()),
      ),
    );

    expect(_exitValue('*****'), findsOneWidget);
    expect(find.textContaining('United Kingdom'), findsNothing);
    expect(find.textContaining('Residential'), findsNothing);
    expect(quality.calls, isEmpty);
    expect(tester.takeException(), isNull);
    // Flush the debounced sync the settings write schedules.
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('no exit IP means a dash and no quality lookup at all', (
    tester,
  ) async {
    final quality = _QualityStub((_) async => _residential);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        entry: const ProbeEntry(phase: ProbePhase.empty),
        quality: quality,
      ),
    );
    await tester.pump();

    expect(_exitValue('—'), findsOneWidget);
    expect(quality.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
