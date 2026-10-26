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

void _expectNoProbeTraces(Map<String, Object?> config) {
  for (final key in ['outbounds', 'inbounds', 'endpoints']) {
    for (final entry in _entries(config, key)) {
      expect(entry['tag'], isNot('probe'));
      expect(entry['tag'], isNot('probe-in'));
    }
  }
  final rules = _entries(config['route'] as Map<String, Object?>, 'rules');
  for (final rule in rules) {
    expect(rule['outbound'], isNot('probe'));
    expect(rule['inbound'], isNot(['probe-in']));
  }
  expect(rules.first, {'protocol': 'dns', 'action': 'hijack-dns'});
  final encoded = jsonEncode(config);
  expect(encoded.contains('probe-in'), isFalse);
  expect(encoded.contains('"probe"'), isFalse);
  expect(encoded.contains('17909'), isFalse);
}

void main() {
  test('a clash render carries no probe channel traces', () {
    final config = renderSingBoxFromClash(_clashSample(), secret: 's').config;
    _expectNoProbeTraces(config);
  });

  test('an IR render with a wireguard endpoint stays probe-free', () {
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
      tunEnabled: true,
    ).config;
    _expectNoProbeTraces(config);
  });
}
