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

import '../../helpers/preferences.dart';
import '../../helpers/test_profiles.dart';

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

const _parent = '⚡ CF前置';
const _child = '⚡ CF前置 · auto';

Map<String, Object?> _panelPayload({required String parentNow}) {
  return {
    'proxies': {
      _parent: {
        'type': 'Selector',
        'now': parentNow,
        'all': [_child, 'CF-01', 'CF-02'],
      },
      _child: {
        'type': 'URLTest',
        'now': 'CF-01',
        'all': ['CF-01', 'CF-02'],
      },
      'CF-01': {'type': 'Http', 'now': ''},
      'CF-02': {'type': 'Shadowsocks', 'now': ''},
      'direct': {'type': 'Direct', 'now': ''},
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('parseSingBoxPanelGroups', () {
    test('keeps group entries with type, now and members only', () {
      final panel = parseSingBoxPanelGroups(_panelPayload(parentNow: 'CF-01'));
      expect(panel.keys, unorderedEquals([_parent, _child]));
      expect(panel[_parent]?.type, 'Selector');
      expect(panel[_parent]?.now, 'CF-01');
      expect(panel[_parent]?.all, [_child, 'CF-01', 'CF-02']);
      expect(panel[_child]?.type, 'URLTest');
      expect(panel[_child]?.now, 'CF-01');
    });

    test('a payload without a proxies map parses to nothing', () {
      expect(parseSingBoxPanelGroups(const {}), isEmpty);
      expect(parseSingBoxPanelGroups(const {'proxies': []}), isEmpty);
    });
  });

  group('singBoxPanelAutoChild', () {
    test('derives the base auto tag', () {
      final panel = parseSingBoxPanelGroups(_panelPayload(parentNow: _child));
      expect(singBoxPanelAutoChild(panel, _parent), _child);
    });

    test('derives the escalated tag when a leaf owns the base tag', () {
      final panel = parseSingBoxPanelGroups({
        'proxies': {
          'Auto': {
            'type': 'Selector',
            'now': 'Auto · auto 2',
            'all': ['Auto · auto 2', 'Auto · auto', 'SS'],
          },
          'Auto · auto': {'type': 'Shadowsocks', 'now': ''},
          'Auto · auto 2': {
            'type': 'URLTest',
            'now': 'SS',
            'all': ['Auto · auto', 'SS'],
          },
          'SS': {'type': 'Shadowsocks', 'now': ''},
        },
      });
      expect(singBoxPanelAutoChild(panel, 'Auto'), 'Auto · auto 2');
    });

    test('falls back to the only URLTest member when underivable', () {
      final panel = parseSingBoxPanelGroups({
        'proxies': {
          'G': {
            'type': 'Selector',
            'now': 'inner',
            'all': ['inner', 'SS'],
          },
          'inner': {
            'type': 'URLTest',
            'now': 'SS',
            'all': ['SS'],
          },
          'SS': {'type': 'Shadowsocks', 'now': ''},
        },
      });
      expect(singBoxPanelAutoChild(panel, 'G'), 'inner');
    });

    test('returns null without a selector parent or a URLTest member', () {
      final panel = parseSingBoxPanelGroups(_panelPayload(parentNow: 'CF-01'));
      expect(singBoxPanelAutoChild(panel, _child), isNull);
      expect(singBoxPanelAutoChild(panel, 'missing'), isNull);
      final noChild = parseSingBoxPanelGroups({
        'proxies': {
          'G': {
            'type': 'Selector',
            'now': 'SS',
            'all': ['SS'],
          },
          'SS': {'type': 'Shadowsocks', 'now': ''},
        },
      });
      expect(singBoxPanelAutoChild(noChild, 'G'), isNull);
    });
  });

  group('panel round trip', () {
    setUp(() async {
      await mockPreferences();
    });

    test(
      'changeProxy to the auto child PUTs it and refreshes the panel table',
      () async {
        var parentNow = 'CF-01';
        var getCount = 0;
        final puts = <({String path, Object? body})>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          if (request.method == 'GET' && request.uri.path == '/proxies') {
            getCount++;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              json.encode(_panelPayload(parentNow: parentNow)),
            );
          } else if (request.method == 'PUT') {
            final decoded = json.decode(body) as Map;
            puts.add((path: request.uri.path, body: decoded));
            parentNow = decoded['name'].toString();
            request.response.statusCode = 204;
          } else {
            request.response.statusCode = 204;
          }
          await request.response.close();
        });
        await AppLocalizations.load(const Locale('en'));
        const profile = Profile(
          id: 1,
          label: 'Test',
          type: ProfileType.url,
          url: 'https://example.com/sub',
          selectedMap: {_parent: 'CF-01'},
          autoUpdateDuration: Duration.zero,
        );
        final container = ProviderContainer(
          overrides: [
            profilesProvider.overrideWith(() => TestProfiles([profile])),
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            groupsProvider.overrideWithValue(const [
              Group(
                name: _parent,
                type: GroupType.URLTest,
                all: [
                  Proxy(name: 'CF-01', type: 'Http'),
                  Proxy(name: 'CF-02', type: 'Shadowsocks'),
                ],
              ),
            ]),
            coreStatusProvider.overrideWithBuild(
              (_, _) => CoreStatus.disconnected,
            ),
            coreHandlerProvider.overrideWithValue(
              CoreController.scoped(_MockCoreHandlerInterface()),
            ),
            singBoxActionProvider.overrideWith(
              () => _BearerSingBoxAction(
                SingBoxClashApi(port: server.port, secret: 'panel-secret'),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(singBoxActionProvider.future);

        final before = await container.read(singBoxPanelGroupsProvider.future);
        expect(before[_parent]?.now, 'CF-01');
        expect(singBoxPanelAutoChild(before, _parent), _child);
        expect(getCount, 1);

        await container
            .read(proxiesActionProvider.notifier)
            .changeProxy(groupName: _parent, proxyName: _child);

        expect(puts, hasLength(1));
        expect(puts.single.path, '/proxies/%E2%9A%A1%20CF%E5%89%8D%E7%BD%AE');
        expect(puts.single.body, {'name': _child});
        expect(container.read(selectedMapProvider)[_parent], _child);

        final after = await container.read(singBoxPanelGroupsProvider.future);
        expect(getCount, 2);
        expect(after[_parent]?.now, _child);
      },
    );
  });
}
