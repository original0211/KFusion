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
        'network': 'ws',
        'ws-opts': {'path': '/ws'},
      },
      {
        'name': 'VLESS',
        'type': 'vless',
        'server': '9.9.9.9',
        'port': 443,
        'uuid': '22222222-3333-4444-5555-666666666666',
        'flow': 'xtls-rprx-vision',
        'tls': true,
        'servername': 'example.com',
        'reality-opts': {'public-key': 'pubkey', 'short-id': 'shortid'},
      },
      {
        'name': 'Trojan',
        'type': 'trojan',
        'server': '10.0.0.1',
        'port': 443,
        'password': 'trojanpass',
        'sni': 'example.com',
      },
      {
        'name': 'HY2',
        'type': 'hysteria2',
        'server': '11.0.0.2',
        'port': 443,
        'password': 'hy2pass',
        'obfs': 'salamander',
        'obfs-password': 'obfspass',
      },
      {
        'name': 'TUIC',
        'type': 'tuic',
        'server': '12.0.0.3',
        'port': 443,
        'uuid': '33333333-4444-5555-6666-777777777777',
        'password': 'tuicpass',
      },
    ],
    'proxy-groups': [
      {
        'name': 'PROXY',
        'type': 'select',
        'proxies': ['SS', 'VMess', 'VLESS', 'Trojan', 'HY2', 'TUIC'],
      },
      {
        'name': 'Auto',
        'type': 'url-test',
        'proxies': ['SS', 'VMess'],
        'url': 'https://www.gstatic.com/generate_204',
        'interval': 300,
        'tolerance': 50,
      },
    ],
    'rules': [
      'DOMAIN,example.com,PROXY',
      'DOMAIN-SUFFIX,google.com,PROXY',
      'DOMAIN-KEYWORD,apple,PROXY',
      'IP-CIDR,1.2.3.0/24,DIRECT,no-resolve',
      'GEOIP,CN,DIRECT',
      'GEOSITE,cn,DIRECT',
      'RULE-SET,https://example.com/rules.yaml,PROXY',
      'MATCH,PROXY',
    ],
  };
}

List<Map<String, Object?>> _outbounds(Map<String, Object?> config) {
  final outbounds = config['outbounds'];
  if (outbounds is List) {
    return [
      for (final entry in outbounds)
        if (entry is Map)
          {
            for (final MapEntry(:key, :value) in entry.entries)
              key.toString(): value,
          },
    ];
  }
  return const [];
}

void main() {
  test('clash sample renders to sing-box json', () {
    final result = renderSingBoxFromClash(
      _clashSample(),
      secret: 'test-secret',
    );
    final config = result.config;
    final outbounds = _outbounds(config);
    final byTag = {
      for (final outbound in outbounds) outbound['tag'].toString(): outbound,
    };
    expect(byTag['SS']?['type'], 'shadowsocks');
    expect(byTag['SS']?['method'], 'aes-256-gcm');
    expect(byTag['VMess']?['type'], 'vmess');
    expect((byTag['VMess']?['transport'] as Map?)?['path'], '/ws');
    expect(byTag['VLESS']?['type'], 'vless');
    expect(byTag['VLESS']?['flow'], 'xtls-rprx-vision');
    expect(
      ((byTag['VLESS']?['tls'] as Map?)?['reality'] as Map?)?['public_key'],
      'pubkey',
    );
    expect(byTag['Trojan']?['type'], 'trojan');
    expect(byTag['HY2']?['type'], 'hysteria2');
    expect(byTag['TUIC']?['type'], 'tuic');
    expect(byTag['PROXY']?['type'], 'selector');
    expect(byTag['Auto']?['type'], 'urltest');
    expect(byTag['Auto']?['interval'], '300s');
    expect(byTag['direct']?['type'], 'direct');
    expect(byTag['block']?['type'], 'block');
    final route = config['route'] as Map;
    final rules = route['rules'] as List;
    expect(rules.length, 6);
    expect(route['final'], 'PROXY');
    final dns = config['dns'] as Map;
    expect((dns['servers'] as List).length, 2);
    expect(dns['final'], 'remote');
    final inbounds = config['inbounds'] as List;
    expect((inbounds.first as Map)['listen_port'], 7890);
    expect(inbounds.where((entry) => (entry as Map)['type'] == 'tun'), isEmpty);
    final clashApi = (config['experimental'] as Map)['clash_api'] as Map;
    expect(clashApi['external_controller'], '127.0.0.1:9091');
    expect(clashApi['secret'], 'test-secret');
    expect(clashApi['cache_file'], true);
    expect(result.unsupported.length, 1);
    expect(result.unsupported.first, contains('RULE-SET'));
  });

  test('tun inbound appears only when enabled', () {
    final result = renderSingBoxFromClash(
      _clashSample(),
      secret: 'test-secret',
      tunEnabled: true,
    );
    final inbounds = result.config['inbounds'] as List;
    expect(
      inbounds.where((entry) => (entry as Map)['type'] == 'tun'),
      hasLength(1),
    );
  });

  test('render then parse roundtrips nodes', () {
    final rendered = renderSingBoxFromClash(
      _clashSample(),
      secret: 'test-secret',
    );
    final parsed = fromSingBox(json.encode(rendered.config));
    final names = parsed.profile.nodes.map((node) => node.name).toList();
    expect(names, ['SS', 'VMess', 'VLESS', 'Trojan', 'HY2', 'TUIC']);
    final types = parsed.profile.nodes.map((node) => node.type).toList();
    expect(types, ['ss', 'vmess', 'vless', 'trojan', 'hysteria2', 'tuic']);
    expect(parsed.profile.nodes.first.params['password'], 'password');
  });

  test('core kind defaults to mihomo and unknown values fall back', () {
    expect(CoreKind.fromValue(null), CoreKind.mihomo);
    expect(CoreKind.fromValue('singbox'), CoreKind.singbox);
    expect(CoreKind.fromValue('bogus'), CoreKind.mihomo);
  });
}
