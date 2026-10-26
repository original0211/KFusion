import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';

Map<String, Object?> _clashSample() {
  return {
    'proxies': [
      {
        'name': 'SS',
        'type': 'ss',
        'server': '1.2.3.4',
        'port': 8388,
        'cipher': 'aes-256-gcm',
        'password': 'password',
      },
      {
        'name': 'VMess',
        'type': 'vmess',
        'server': '5.6.7.8',
        'port': 443,
        'uuid': '11111111-2222-3333-4444-555555555555',
        'cipher': 'auto',
      },
    ],
    'proxy-groups': [
      {
        'name': 'PROXY',
        'type': 'select',
        'proxies': ['SS', 'VMess'],
      },
      {
        'name': 'Auto',
        'type': 'url-test',
        'proxies': ['SS', 'VMess'],
        'url': 'https://www.gstatic.com/generate_204',
        'interval': 300,
      },
    ],
    'rules': ['DOMAIN,example.com,PROXY', 'MATCH,PROXY'],
  };
}

List<Map<String, Object?>> _entries(Map<String, Object?> config, String key) {
  final value = config[key];
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is Map)
        {
          for (final MapEntry(:key, :value) in entry.entries)
            key.toString(): value,
        },
  ];
}

Map<String, Object?> _stripProbe(Map<String, Object?> config) {
  final stripped = <String, Object?>{...config};
  stripped['outbounds'] = [
    for (final entry in _entries(config, 'outbounds'))
      if (entry['tag'] != singBoxProbeSelectorTag) entry,
  ];
  stripped['inbounds'] = [
    for (final entry in _entries(config, 'inbounds'))
      if (entry['tag'] != singBoxProbeInboundTag) entry,
  ];
  final route = config['route'];
  if (route is Map) {
    final routeMap = <String, Object?>{
      for (final MapEntry(:key, :value) in route.entries) key.toString(): value,
    };
    routeMap['rules'] = [
      for (final rule in _entries(routeMap, 'rules'))
        if (rule['outbound'] != singBoxProbeSelectorTag) rule,
    ];
    stripped['route'] = routeMap;
  }
  return stripped;
}

void main() {
  test('injects a probe selector over leaf outbounds only', () {
    final config = renderSingBoxFromClash(_clashSample(), secret: 's').config;
    final outbounds = _entries(config, 'outbounds');
    final probe = outbounds.singleWhere(
      (entry) => entry['tag'] == singBoxProbeSelectorTag,
    );
    expect(probe['type'], 'selector');
    expect(probe['outbounds'], ['SS', 'VMess', 'direct']);

    final inbound = _entries(
      config,
      'inbounds',
    ).singleWhere((entry) => entry['tag'] == singBoxProbeInboundTag);
    expect(inbound['type'], 'mixed');
    expect(inbound['listen'], '127.0.0.1');
    expect(inbound['listen_port'], singBoxProbePort);

    final rules = _entries(config['route'] as Map<String, Object?>, 'rules');
    expect(rules.first, {
      'inbound': [singBoxProbeInboundTag],
      'outbound': singBoxProbeSelectorTag,
    });
    expect(rules[1], {'protocol': 'dns', 'action': 'hijack-dns'});
  });

  test('injection leaves every pre-existing entry untouched', () {
    final withProbe = renderSingBoxFromClash(
      _clashSample(),
      secret: 's',
    ).config;
    final withoutProbe = renderSingBoxFromClash(
      _clashSample(),
      secret: 's',
      probeEnabled: false,
    ).config;
    expect(jsonEncode(_stripProbe(withProbe)), jsonEncode(withoutProbe));
  });

  test('a user group named like the probe channel suppresses injection', () {
    final clash = _clashSample();
    (clash['proxy-groups'] as List).add({
      'name': 'probe',
      'type': 'select',
      'proxies': ['SS'],
    });
    final config = renderSingBoxFromClash(clash, secret: 's').config;
    final tags = [
      for (final entry in _entries(config, 'outbounds')) entry['tag'],
    ];
    expect(tags.where((tag) => tag == singBoxProbeSelectorTag), hasLength(1));
    expect(
      _entries(
        config,
        'inbounds',
      ).where((entry) => entry['tag'] == singBoxProbeInboundTag),
      isEmpty,
    );
    final withoutProbe = renderSingBoxFromClash(
      clash,
      secret: 's',
      probeEnabled: false,
    ).config;
    expect(jsonEncode(config), jsonEncode(withoutProbe));
  });

  test('wireguard endpoints join the probe selector as leaves', () {
    final config = renderSingBox(
      const IrProfile(
        nodes: [
          IrNode(
            name: 'WG',
            type: 'wireguard',
            server: '10.0.0.1',
            port: 51820,
            params: {'ip': '10.0.0.2', 'private-key': 'k', 'public-key': 'p'},
          ),
        ],
      ),
      secret: 's',
    ).config;
    final probe = _entries(
      config,
      'outbounds',
    ).singleWhere((entry) => entry['tag'] == singBoxProbeSelectorTag);
    expect(probe['outbounds'], ['direct', 'WG']);
  });

  test('a custom probe port lands on the probe inbound only', () {
    final config = renderSingBoxFromClash(
      _clashSample(),
      secret: 's',
      probePort: 19090,
    ).config;
    final inbound = _entries(
      config,
      'inbounds',
    ).singleWhere((entry) => entry['tag'] == singBoxProbeInboundTag);
    expect(inbound['listen_port'], 19090);
    final mixed = _entries(
      config,
      'inbounds',
    ).singleWhere((entry) => entry['tag'] == 'mixed-in');
    expect(mixed['listen_port'], 7890);
  });
}
