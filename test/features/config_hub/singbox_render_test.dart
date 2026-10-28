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
        'reality-opts': {
          'public-key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          'short-id': '0123456789abcdef',
        },
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
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    expect(
      ((byTag['VLESS']?['tls'] as Map?)?['utls'] as Map?)?['fingerprint'],
      'chrome',
    );
    expect(byTag['Trojan']?['type'], 'trojan');
    expect(byTag['HY2']?['type'], 'hysteria2');
    expect(byTag['TUIC']?['type'], 'tuic');
    expect(byTag['PROXY']?['type'], 'selector');
    expect(byTag['Auto']?['type'], 'urltest');
    expect(byTag['Auto']?['interval'], '300s');
    expect(byTag['direct']?['type'], 'direct');
    expect(byTag.containsKey('block'), isFalse);
    final route = config['route'] as Map;
    final rules = route['rules'] as List;
    expect(rules.length, 7);
    expect((rules.first as Map)['protocol'], 'dns');
    expect((rules.first as Map)['action'], 'hijack-dns');
    expect(route['final'], 'PROXY');
    final geoRules = [
      for (final entry in rules.skip(1))
        if ((entry as Map)['rule_set'] != null) entry,
    ];
    expect(geoRules.length, 2);
    final ruleSetTags = {
      for (final def in route['rule_set'] as List)
        ((def as Map)['tag'] as String),
    };
    expect(ruleSetTags, containsAll(['geoip-cn', 'geosite-cn']));
    final dns = config['dns'] as Map;
    final dnsServers = dns['servers'] as List;
    expect(dnsServers.length, 3);
    expect((dnsServers[0] as Map)['type'], 'https');
    expect((dnsServers[2] as Map)['type'], 'fakeip');
    expect(dns['final'], 'remote');
    final inbounds = config['inbounds'] as List;
    expect((inbounds.first as Map)['listen_port'], 7890);
    expect(inbounds.where((entry) => (entry as Map)['type'] == 'tun'), isEmpty);
    final experimental = config['experimental'] as Map;
    final clashApi = experimental['clash_api'] as Map;
    expect(clashApi['external_controller'], '127.0.0.1:9091');
    expect(clashApi['secret'], 'test-secret');
    expect(clashApi.containsKey('cache_file'), isFalse);
    expect((experimental['cache_file'] as Map)['enabled'], true);
    expect(result.unsupported.length, 1);
    expect(result.unsupported.first, contains('RULE-SET'));
  });

  test('rendered config carries no sing-box 1.14 removed constructs', () {
    final result = renderSingBoxFromClash(
      _clashSample(),
      secret: 'test-secret',
      tunEnabled: true,
    );
    final keys = <String>{};
    void collect(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          keys.add(entry.key.toString());
          collect(entry.value);
        }
      } else if (value is List) {
        for (final entry in value) {
          collect(entry);
        }
      }
    }

    collect(result.config);
    expect(keys, isNot(contains('geosite')));
    expect(keys, isNot(contains('geoip')));
    expect(keys, isNot(contains('inet4_address')));
    expect(keys, isNot(contains('inet6_address')));
    expect(keys, isNot(contains('fakeip'))); // the dns-level block is a key
    final outbounds = _outbounds(result.config);
    expect(outbounds.where((outbound) => outbound['type'] == 'dns'), isEmpty);
    expect(outbounds.where((outbound) => outbound['type'] == 'block'), isEmpty);
    final dns = result.config['dns'] as Map;
    for (final server in dns['servers'] as List) {
      expect((server as Map).containsKey('address'), isFalse);
    }
    final tun =
        (result.config['inbounds'] as List).firstWhere(
              (entry) => (entry as Map)['type'] == 'tun',
            )
            as Map;
    expect(tun['address'], ['172.19.0.1/30']);
  });

  test('DIRECT members map and REJECT members are dropped with a note', () {
    final clash = _clashSample();
    (clash['proxy-groups'] as List).add({
      'name': 'Pick',
      'type': 'select',
      'proxies': ['DIRECT', 'REJECT', 'SS'],
    });
    (clash['rules'] as List).insert(0, 'DOMAIN-SUFFIX,ads.example.com,REJECT');
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final outbounds = _outbounds(result.config);
    final pick = outbounds.firstWhere((outbound) => outbound['tag'] == 'Pick');
    expect(pick['outbounds'], ['direct', 'SS']);
    expect(
      result.unsupported.any((note) => note.contains('REJECT in proxy-group')),
      isTrue,
    );
    final rules = (result.config['route'] as Map)['rules'] as List;
    final reject =
        rules.firstWhere((entry) => (entry as Map)['action'] == 'reject')
            as Map;
    expect(reject['domain_suffix'], ['ads.example.com']);
    expect(reject.containsKey('outbound'), isFalse);
  });

  test('a MATCH to REJECT ends the rules with a reject action', () {
    final clash = _clashSample();
    final rules = clash['rules'] as List;
    rules[rules.length - 1] = 'MATCH,REJECT';
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final route = result.config['route'] as Map;
    final rendered = route['rules'] as List;
    expect((rendered.last as Map)['action'], 'reject');
    final outbounds = _outbounds(result.config);
    expect(outbounds.any((outbound) => outbound['tag'] == 'block'), isFalse);
    expect(route['final'], isNot('block'));
  });

  test('a group of only REJECT members is dropped entirely', () {
    final clash = _clashSample();
    (clash['proxy-groups'] as List).add({
      'name': 'Deny',
      'type': 'select',
      'proxies': ['REJECT'],
    });
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final outbounds = _outbounds(result.config);
    expect(outbounds.any((outbound) => outbound['tag'] == 'Deny'), isFalse);
  });

  test('wireguard node renders as an endpoint, not an outbound', () {
    final clash = _clashSample();
    (clash['proxies'] as List).add({
      'name': 'WG',
      'type': 'wireguard',
      'server': '5.5.5.5',
      'port': 51820,
      'ip': '10.0.0.2',
      'private-key': 'privatekey',
      'public-key': 'publickey',
    });
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final outbounds = _outbounds(result.config);
    expect(outbounds.where((outbound) => outbound['tag'] == 'WG'), isEmpty);
    final endpoints = result.config['endpoints'] as List;
    expect(endpoints.length, 1);
    final endpoint = endpoints.first as Map;
    expect(endpoint['type'], 'wireguard');
    expect(endpoint['address'], ['10.0.0.2/32']);
    final peer = (endpoint['peers'] as List).first as Map;
    expect(peer['address'], '5.5.5.5');
    expect(peer['port'], 51820);
    expect(peer['public_key'], 'publickey');
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

  test('GEOIP LAN renders as ip_is_private, never as a remote rule set', () {
    final clash = _clashSample();
    (clash['rules'] as List).insert(0, 'GEOIP,LAN,DIRECT');
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final route = result.config['route'] as Map;
    final rules = route['rules'] as List;
    final lanRule = rules.firstWhere(
      (entry) => (entry as Map)['ip_is_private'] == true,
    ) as Map;
    expect(lanRule['outbound'], 'direct');
    final ruleSetTags = {
      for (final def in route['rule_set'] as List)
        ((def as Map)['tag'] as String),
    };
    expect(ruleSetTags, isNot(contains('geoip-lan')));
  });

  test('remote rule set urls are exactly the verified upstream files', () {
    final clash = _clashSample();
    (clash['rules'] as List).insert(0, 'GEOIP,LAN,DIRECT');
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final route = result.config['route'] as Map;
    final urls = {
      for (final def in route['rule_set'] as List)
        ((def as Map)['url'] as String),
    };
    // Verified live (HTTP 200) on 2026-10-28; sing-geoip publishes codes only.
    expect(urls, {
      'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs',
    });
  });
}
