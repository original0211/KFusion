import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/features/config_hub/singbox_degradations.dart';
import 'package:kfusion/features/config_hub/singbox_render.dart';

const _yaml = '''
proxies:
  - {name: OVPN, type: openvpn, server: 203.0.113.1, port: 1194}
  - {name: WG-BAD, type: wireguard, server: 203.0.113.4, port: 51820, public-key: k, private-key: p}
  - {name: SS-1, type: ss, server: 203.0.113.2, port: 8388, cipher: aes-256-gcm, password: pw}
  - {name: SS-CHAIN, type: ss, server: 203.0.113.5, port: 8388, cipher: aes-256-gcm, password: pw, dialer-proxy: OVPN}
proxy-groups:
  - {name: FallbackG, type: fallback, proxies: [SS-1]}
  - {name: Pick, type: select, proxies: [OVPN, SS-1]}
rules:
  - DOMAIN-SUFFIX,example.com,Pick
  - MATCH,Pick
''';

List<(SingBoxDegradationKind, String, String)> _triples(
  List<SingBoxDegradation> items,
) => [for (final item in items) (item.kind, item.name, item.reason)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the scan is the switch render ledger, item for item', () {
    final doc = loadPlainYaml(_yaml);
    final clash = {
      for (final entry in (doc as Map).entries)
        entry.key.toString(): entry.value,
    };
    final rendered = renderSingBoxFromClash(clash, secret: '');
    expect(
      _triples(singBoxDegradationsOf(_yaml)),
      _triples(rendered.degradations),
    );
    expect(
      singBoxDegradationsOf(_yaml).length,
      rendered.unsupported.length,
      reason: 'the list count and the core switch card count share a source',
    );
  });

  test('the scan names every degradation kind the fixture earns', () {
    final kinds = singBoxDegradationsOf(_yaml).map((d) => d.kind).toSet();
    expect(
      kinds,
      containsAll(<SingBoxDegradationKind>{
        SingBoxDegradationKind.nodeProtocol,
        SingBoxDegradationKind.nodeUnusable,
        SingBoxDegradationKind.groupType,
        SingBoxDegradationKind.groupMember,
        SingBoxDegradationKind.chain,
        SingBoxDegradationKind.routing,
      }),
    );
  });

  test('an unusable or empty file scans as an empty ledger', () {
    expect(singBoxDegradationsOf(''), isEmpty);
    expect(singBoxDegradationsOf('not: [valid'), isEmpty);
    expect(singBoxDegradationsOf('proxies: []'), isEmpty);
  });

  group('store', () {
    late Directory dir;
    late SingBoxDegradationStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('degradations');
      store = SingBoxDegradationStore(profilesDir: () async => dir.path);
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('round-trips a ledger and reads absence as empty', () async {
      final items = singBoxDegradationsOf(_yaml);
      expect(items, isNotEmpty);
      await store.write(7, items);
      expect(_triples(await store.read(7)), _triples(items));
      expect(await store.read(8), isEmpty);
    });

    test('an empty ledger leaves no file, and remove clears one', () async {
      final file = File('${dir.path}/7.degradations.json');
      await store.write(7, singBoxDegradationsOf(_yaml));
      expect(await file.exists(), isTrue);
      await store.write(7, const []);
      expect(await file.exists(), isFalse);
      await store.write(7, singBoxDegradationsOf(_yaml));
      await store.remove(7);
      expect(await file.exists(), isFalse);
      expect(await store.read(7), isEmpty);
    });

    test('the view-model provider serves the stored ledger', () async {
      final container = ProviderContainer(
        overrides: [singBoxDegradationStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final items = singBoxDegradationsOf(_yaml);
      await store.write(7, items);
      final served = await container.read(
        profileDegradationsProvider(7).future,
      );
      expect(_triples(served), _triples(items));
      expect(
        await container.read(profileDegradationsProvider(8).future),
        isEmpty,
      );
    });
  });
}
