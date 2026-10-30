import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/core/controller.dart';
import 'package:kfusion/core/interface.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/preferences.dart';
import '../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _BearerSingBoxAction extends SingBoxAction {
  _BearerSingBoxAction(this._api);

  final SingBoxClashApi _api;

  @override
  Future<SingBoxStatus> build() async =>
      const SingBoxStatus(state: SingBoxState.running);

  @override
  SingBoxClashApi? get api => _api;
}

const _profile = Profile(
  id: 1,
  label: 'Test',
  type: ProfileType.url,
  url: 'https://example.com/sub',
  selectedMap: {'Home': 'JP-03'},
  autoUpdateDuration: Duration.zero,
);

const _groups = [
  Group(
    name: 'Home',
    type: GroupType.Selector,
    all: [
      Proxy(name: 'JP-03', type: 'Shadowsocks'),
      Proxy(name: 'HK-01', type: 'Shadowsocks'),
    ],
  ),
];

typedef _RecordedRequest = ({
  String method,
  String path,
  Map<String, String> query,
  String body,
});

class _Panel {
  _Panel({this.proxyStatus = 204});

  final int proxyStatus;
  final List<_RecordedRequest> requests = [];
  late final HttpServer server;

  Future<SingBoxClashApi> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        body: body,
      ));
      if (request.method == 'PUT') {
        request.response.statusCode = proxyStatus;
        if (proxyStatus != 204) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            json.encode({'message': 'Selector update error: not found'}),
          );
        }
      } else if (request.uri.path.endsWith('/delay')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({'delay': 123}));
      } else {
        request.response.statusCode = 204;
      }
      await request.response.close();
    });
    return SingBoxClashApi(port: server.port, secret: 'panel-secret');
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding's mock HttpClient would answer every panel request
  // with a canned 400; the panel under test is a real local server.
  HttpOverrides.global = null;

  setUpAll(() {
    registerFallbackValue(
      const ChangeProxyParams(groupName: '', proxyName: ''),
    );
  });

  setUp(() async {
    await mockPreferences();
  });

  Future<({ProviderContainer container, _MockCoreHandlerInterface core})> boot(
    _Panel panel,
  ) async {
    await AppLocalizations.load(const Locale('en'));
    final api = await panel.start();
    addTearDown(panel.stop);
    final core = _MockCoreHandlerInterface();
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(const [_profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => _profile.id),
        groupsProvider.overrideWithValue(_groups),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.disconnected),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        singBoxActionProvider.overrideWith(() => _BearerSingBoxAction(api)),
      ],
    );
    addTearDown(container.dispose);
    // The dashboard watches the action from the first frame in the app;
    // here the running status has to land before any control call reads it.
    await container.read(singBoxActionProvider.future);
    return (container: container, core: core);
  }

  test(
    'changeProxy under a sing-box bearer lands on the panel, not mihomo',
    () async {
      final panel = _Panel();
      final (:container, :core) = await boot(panel);

      await container
          .read(proxiesActionProvider.notifier)
          .changeProxy(groupName: 'Home', proxyName: 'HK-01');

      final put = panel.requests.where((r) => r.method == 'PUT').toList();
      expect(put, hasLength(1));
      expect(put.single.path, '/proxies/Home');
      expect(json.decode(put.single.body), {'name': 'HK-01'});
      verifyNever(() => core.changeProxy(any()));
      expect(container.read(selectedMapProvider)['Home'], 'HK-01');
    },
  );

  test('a rejected panel selection rolls the selection back', () async {
    final panel = _Panel(proxyStatus: 400);
    final (:container, :core) = await boot(panel);

    await container
        .read(proxiesActionProvider.notifier)
        .changeProxy(groupName: 'Home', proxyName: 'NOPE');

    expect(container.read(selectedMapProvider)['Home'], 'JP-03');
    verifyNever(() => core.changeProxy(any()));
  });

  test('changeMode under a sing-box bearer PATCHes the panel mode', () async {
    final panel = _Panel();
    final (:container, :core) = await boot(panel);
    // The app keeps the patch config watched through configProvider; a
    // bare container has to hold the subscription itself.
    final subscription = container.listen(patchClashConfigProvider, (_, _) {});
    addTearDown(subscription.close);

    container.read(setupActionProvider.notifier).changeMode(Mode.global);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final patch = panel.requests.where((r) => r.method == 'PATCH').toList();
    expect(patch, hasLength(1));
    expect(patch.single.path, '/configs');
    expect(json.decode(patch.single.body), {'mode': 'Global'});
    expect(container.read(patchClashConfigProvider).mode, Mode.global);
  });

  test(
    'delay tests under a sing-box bearer measure through the panel',
    () async {
      final panel = _Panel();
      final (:container, :core) = await boot(panel);

      await container.read(proxiesActionProvider.notifier).delayTest([
        _groups.single.all.first,
      ]);

      final delayCall = panel.requests
          .where((r) => r.path.endsWith('/delay'))
          .toList();
      expect(delayCall, hasLength(1));
      expect(delayCall.single.path, '/proxies/JP-03/delay');
      verifyNever(() => core.asyncTestDelay(any(), any()));
      final delayMap = container.read(delayDataSourceProvider);
      expect(delayMap[delayCall.single.query['url']]?['JP-03'], 123);
    },
  );
}
