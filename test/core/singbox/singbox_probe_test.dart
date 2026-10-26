import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/common/service_probe.dart';
import 'package:kfusion/core/singbox/singbox_probe.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';

class _FakeApi extends SingBoxClashApi {
  _FakeApi(this.payload) : super(port: 1, secret: 's');

  final Map<String, Object?> payload;
  final selections = <(String, String)>[];

  @override
  Future<Map<String, Object?>> getProxies() async => payload;

  @override
  Future<void> selectProxy(String group, String name) async {
    selections.add((group, name));
  }
}

Map<String, Object?> _payload() {
  return {
    'proxies': {
      'PROXY': {'type': 'Selector', 'now': 'Auto'},
      'Auto': {'type': 'URLTest', 'now': 'SS'},
      'SS': {'type': 'Shadowsocks'},
      'direct': {'type': 'Direct'},
      'REJECT': {'type': 'Reject'},
      'LoopA': {'type': 'Selector', 'now': 'LoopB'},
      'LoopB': {'type': 'Selector', 'now': 'LoopA'},
      'Broken': {'type': 'Selector', 'now': ''},
    },
  };
}

Map<String, Object?> _proxies() {
  return _payload()['proxies'] as Map<String, Object?>;
}

void main() {
  group('resolveSingBoxLeaf', () {
    test('follows group chains down to the leaf', () {
      expect(resolveSingBoxLeaf(_proxies(), 'PROXY'), 'SS');
      expect(resolveSingBoxLeaf(_proxies(), 'SS'), 'SS');
    });

    test('maps DIRECT onto the direct outbound', () {
      expect(resolveSingBoxLeaf(_proxies(), 'DIRECT'), 'direct');
    });

    test('rejects rejects, cycles, broken and missing names', () {
      expect(resolveSingBoxLeaf(_proxies(), 'REJECT'), isNull);
      expect(resolveSingBoxLeaf(_proxies(), 'LoopA'), isNull);
      expect(resolveSingBoxLeaf(_proxies(), 'Broken'), isNull);
      expect(resolveSingBoxLeaf(_proxies(), 'Nope'), isNull);
    });
  });

  group('lookupSingBoxOutboundIp', () {
    test('points the probe group at the leaf and races the echoes', () async {
      final api = _FakeApi(_payload());
      final result = await lookupSingBoxOutboundIp(
        api,
        'PROXY',
        probeGroup: 'probe',
        probePort: 17909,
        echoFetch: (url) async {
          if (url.host == 'www.cloudflare.com') {
            return 'ip=203.0.113.7\nloc=US\n';
          }
          return null;
        },
      );
      expect(api.selections, [('probe', 'SS')]);
      expect(result, isNotNull);
      expect(result!.chains, ['SS']);
      expect(parseOutboundIp(result)?.ip, '203.0.113.7');
    });

    test('an unresolvable node is never selected or fetched', () async {
      final api = _FakeApi(_payload());
      var fetched = false;
      final result = await lookupSingBoxOutboundIp(
        api,
        'REJECT',
        probeGroup: 'probe',
        probePort: 17909,
        echoFetch: (url) async {
          fetched = true;
          return 'ip=203.0.113.7\n';
        },
      );
      expect(result, isNull);
      expect(api.selections, isEmpty);
      expect(fetched, isFalse);
    });

    test('no parseable echo means no answer', () async {
      final api = _FakeApi(_payload());
      final result = await lookupSingBoxOutboundIp(
        api,
        'SS',
        probeGroup: 'probe',
        probePort: 17909,
        echoFetch: (url) async => 'not an echo',
      );
      expect(result, isNull);
      expect(api.selections, [('probe', 'SS')]);
    });
  });
}
