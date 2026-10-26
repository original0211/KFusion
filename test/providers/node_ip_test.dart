@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/common/preferences.dart';
import 'package:kfusion/core/controller.dart';
import 'package:kfusion/core/interface.dart';
import 'package:kfusion/core/singbox/singbox.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/core_kind.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/features/config_hub/singbox_render.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/ip_quality.dart';
import 'package:kfusion/providers/node_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

class _SingBoxKind extends ActiveCoreKindNotifier {
  @override
  Future<CoreKind> build() async => CoreKind.singbox;
}

class _FakeSingBoxAction extends SingBoxAction {
  _FakeSingBoxAction(this._api);

  final SingBoxClashApi _api;

  @override
  SingBoxClashApi? get api => _api;

  @override
  Future<SingBoxStatus> build() async =>
      const SingBoxStatus(state: SingBoxState.running);
}

const _answer = OutboundIpResult(
  url: 'https://www.cloudflare.com/cdn-cgi/trace',
  body: 'ip=2.2.2.2\nloc=US\n',
  chains: ['HK-01'],
  coreEpoch: 1,
  picksVersion: 1,
);

Future<void> _until(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met within 30s');
    }
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const OutboundIpParams(timeout: 0));
    // The sing-box case drives real loopback servers; the test binding's
    // mock HttpClient would answer them all with 400.
    HttpOverrides.global = null;
  });

  test('mirrors the mihomo probe and classifies by exit IP', () async {
    final core = _MockCore();
    when(() => core.outboundIp(any())).thenAnswer((_) async => _answer);
    final container = ProviderContainer(
      overrides: [
        routeTrackerProvider.overrideWithBuild(
          (_, _) => const RouteState(
            coreEpoch: 1,
            picksVersion: 1,
            hostEpoch: 1,
            proxied: true,
            synced: true,
            live: true,
          ),
        ),
        currentProfileProvider.overrideWith((ref) => null),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        ipQualityProvider.overrideWith(
          (ref, ip) async => IpQuality(
            ip: ip,
            source: IpQualitySource.ipApiCom,
            type: IpType.hosting,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(nodeIpSweeperProvider, (_, _) {});

    container.read(nodeIpSweeperProvider.notifier).watch('HK-01');

    await _until(
      () =>
          container.read(nodeIpSweeperProvider)['HK-01']?.type ==
          IpType.hosting,
    );
    final reading = container.read(nodeIpSweeperProvider)['HK-01'];
    expect(reading?.phase, ProbePhase.fresh);
    expect(reading?.ip, '2.2.2.2');
  });

  test('turning the probe setting off clears every reading', () async {
    final core = _MockCore();
    when(() => core.outboundIp(any())).thenAnswer((_) async => _answer);
    final container = ProviderContainer(
      overrides: [
        routeTrackerProvider.overrideWithBuild(
          (_, _) => const RouteState(
            coreEpoch: 1,
            picksVersion: 1,
            hostEpoch: 1,
            proxied: true,
            synced: true,
            live: true,
          ),
        ),
        currentProfileProvider.overrideWith((ref) => null),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        ipQualityProvider.overrideWith(
          (ref, ip) async => IpQuality(
            ip: ip,
            source: IpQualitySource.ipApiCom,
            type: IpType.hosting,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(nodeIpSweeperProvider, (_, _) {});
    final sweeper = container.read(nodeIpSweeperProvider.notifier);
    sweeper.watch('HK-01');
    await _until(
      () => container.read(nodeIpSweeperProvider)['HK-01']?.ip == '2.2.2.2',
    );

    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(probeNodeIpType: false));
    await pumpEventQueue();

    expect(container.read(nodeIpSweeperProvider), isEmpty);
  });

  test('a fresh persisted mapping answers without probing', () async {
    final stamp = DateTime(2026, 10, 26, 12);
    SharedPreferences.setMockInitialValues({
      'nodeIpMap': json.encode({
        '7': {
          'stamp': stamp.millisecondsSinceEpoch,
          'nodes': {
            'HK-01': {
              'ip': '9.9.9.9',
              'ts': DateTime.now().millisecondsSinceEpoch,
            },
          },
        },
      }),
    });
    await Preferences().rebind();
    final core = _MockCore();
    final container = ProviderContainer(
      overrides: [
        currentProfileProvider.overrideWith(
          (ref) => Profile(
            id: 7,
            autoUpdateDuration: Duration.zero,
            lastUpdateDate: stamp,
          ),
        ),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        ipQualityProvider.overrideWith(
          (ref, ip) async => IpQuality(
            ip: ip,
            source: IpQualitySource.ipApiCom,
            type: IpType.residential,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(nodeIpSweeperProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pumpEventQueue();

    container.read(nodeIpSweeperProvider.notifier).watch('HK-01');

    await _until(
      () =>
          container.read(nodeIpSweeperProvider)['HK-01']?.type ==
          IpType.residential,
    );
    expect(container.read(nodeIpSweeperProvider)['HK-01']?.ip, '9.9.9.9');
    verifyNever(() => core.outboundIp(any()));
  });

  test('probes a sing-box node through the injected channel', () async {
    final selections = <String>[];
    final clashServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => clashServer.close(force: true));
    clashServer.listen((request) async {
      if (request.method == 'PUT') {
        final body = await utf8.decoder.bind(request).join();
        selections.add(body);
        request.response.statusCode = 204;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          json.encode({
            'proxies': {
              'SS': {'type': 'Shadowsocks', 'now': ''},
              'probe': {'type': 'Selector', 'now': 'SS'},
            },
          }),
        );
      }
      await request.response.close();
    });
    final proxyServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      singBoxProbePort,
    );
    addTearDown(() => proxyServer.close(force: true));
    proxyServer.listen((request) async {
      if (request.method == 'CONNECT') {
        request.response.statusCode = 405;
      } else if (request.uri.host == 'ip-api.com') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          json.encode({'query': '203.0.113.9', 'countryCode': 'US'}),
        );
      } else {
        request.response.statusCode = 502;
      }
      await request.response.close();
    });
    final container = ProviderContainer(
      overrides: [
        currentProfileProvider.overrideWith((ref) => null),
        activeCoreKindProvider.overrideWith(_SingBoxKind.new),
        singBoxActionProvider.overrideWith(
          () => _FakeSingBoxAction(
            SingBoxClashApi(port: clashServer.port, secret: 's'),
          ),
        ),
        ipQualityProvider.overrideWith(
          (ref, ip) async => IpQuality(
            ip: ip,
            source: IpQualitySource.ipApiCom,
            type: IpType.residential,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(nodeIpSweeperProvider, (_, _) {});

    container.read(nodeIpSweeperProvider.notifier).watch('SS');

    await _until(
      () =>
          container.read(nodeIpSweeperProvider)['SS']?.type ==
          IpType.residential,
    );
    final reading = container.read(nodeIpSweeperProvider)['SS'];
    expect(reading?.ip, '203.0.113.9');
    expect(selections, ['{"name":"SS"}']);
  });
}
