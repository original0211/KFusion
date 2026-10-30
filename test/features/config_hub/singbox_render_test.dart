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

List<SingBoxDegradation> _degradationsOf(
  SingBoxRenderResult result,
  SingBoxDegradationKind kind,
) {
  return [
    for (final degradation in result.degradations)
      if (degradation.kind == kind) degradation,
  ];
}

void main() {
  test('clash sample renders to sing-box json under the contract', () {
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
    expect(route['final'], 'PROXY');
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
    // The eight source rule lines are not translated; one aggregate
    // routing degradation stands in for the whole routing brain.
    expect(result.degradations.length, 1);
    final routing = result.degradations.single;
    expect(routing.kind, SingBoxDegradationKind.routing);
    expect(routing.reason, contains('8'));
    expect(result.unsupported.length, 1);
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

  test('every contract node type renders; off-contract types degrade', () {
    Map<String, Object?> node(
      String name,
      String type, [
      Map<String, Object?> params = const {},
    ]) => {
      'name': name,
      'type': type,
      'server': '1.1.1.1',
      'port': 443,
      ...params,
    };
    final clash = <String, Object?>{
      'proxies': [
        node('N-ss', 'ss', {'cipher': 'aes-256-gcm', 'password': 'p'}),
        node('N-vmess', 'vmess', {'uuid': 'u'}),
        node('N-vless', 'vless', {'uuid': 'u'}),
        node('N-trojan', 'trojan', {'password': 'p'}),
        node('N-hysteria2', 'hysteria2', {'password': 'p'}),
        node('N-tuic', 'tuic', {'uuid': 'u', 'password': 'p'}),
        node('N-wireguard', 'wireguard', {
          'ip': '10.0.0.2',
          'private-key': 'k',
          'public-key': 'p',
        }),
        node('N-socks5', 'socks5'),
        node('N-http', 'http'),
        node('N-openvpn', 'openvpn'),
        node('N-snell', 'snell'),
        node('N-ssr', 'ssr'),
        node('N-anytls', 'anytls'),
      ],
    };
    expect(
      singBoxContractNodeTypes,
      containsAll([
        'ss',
        'vmess',
        'vless',
        'trojan',
        'hysteria2',
        'tuic',
        'wireguard',
        'socks5',
        'http',
      ]),
    );
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final outbounds = _outbounds(result.config);
    final types = {
      for (final outbound in outbounds)
        outbound['tag'].toString(): outbound['type'],
    };
    expect(types['N-ss'], 'shadowsocks');
    expect(types['N-vmess'], 'vmess');
    expect(types['N-vless'], 'vless');
    expect(types['N-trojan'], 'trojan');
    expect(types['N-hysteria2'], 'hysteria2');
    expect(types['N-tuic'], 'tuic');
    expect(types['N-socks5'], 'socks');
    expect(types['N-http'], 'http');
    final endpoints = result.config['endpoints'] as List;
    expect((endpoints.single as Map)['tag'], 'N-wireguard');
    for (final name in ['N-openvpn', 'N-snell', 'N-ssr', 'N-anytls']) {
      expect(types.containsKey(name), isFalse, reason: name);
    }
    final dropped = _degradationsOf(
      result,
      SingBoxDegradationKind.nodeProtocol,
    );
    expect(dropped.map((d) => d.name), [
      'N-openvpn',
      'N-snell',
      'N-ssr',
      'N-anytls',
    ]);
    _expectAllReferencesResolve(result.config);
  });

  test('route template sends private and CN traffic direct', () {
    final result = renderSingBoxFromClash(
      _clashSample(),
      secret: 'test-secret',
    );
    final route = result.config['route'] as Map;
    final rules = route['rules'] as List;
    expect(rules.length, 6);
    expect((rules[0] as Map)['protocol'], 'dns');
    expect((rules[0] as Map)['action'], 'hijack-dns');
    // The clash_mode pair rides under the DNS hijack: without them the
    // panel mode switch would have no mode to select in sing-box.
    expect((rules[1] as Map)['clash_mode'], 'Global');
    expect((rules[1] as Map)['outbound'], route['final']);
    expect((rules[2] as Map)['clash_mode'], 'Direct');
    expect((rules[2] as Map)['outbound'], 'direct');
    expect((rules[3] as Map)['ip_is_private'], isTrue);
    expect((rules[3] as Map)['outbound'], 'direct');
    expect((rules[4] as Map)['rule_set'], ['geoip-cn']);
    expect((rules[4] as Map)['outbound'], 'direct');
    expect((rules[5] as Map)['rule_set'], ['geosite-cn']);
    expect((rules[5] as Map)['outbound'], 'direct');
    final ruleSetTags = {
      for (final def in route['rule_set'] as List)
        ((def as Map)['tag'] as String),
    };
    expect(ruleSetTags, {'geoip-cn', 'geosite-cn'});
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

  test('a profile with no rules records no routing degradation', () {
    final clash = _clashSample();
    clash.remove('rules');
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    expect(result.degradations, isEmpty);
    expect(result.unsupported, isEmpty);
  });

  test('DIRECT members map and REJECT members are pruned with a note', () {
    final clash = _clashSample();
    (clash['proxy-groups'] as List).add({
      'name': 'Pick',
      'type': 'select',
      'proxies': ['DIRECT', 'REJECT', 'SS'],
    });
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final outbounds = _outbounds(result.config);
    final pick = outbounds.firstWhere((outbound) => outbound['tag'] == 'Pick');
    expect(pick['outbounds'], ['direct', 'SS']);
    final memberDrops = _degradationsOf(
      result,
      SingBoxDegradationKind.groupMember,
    );
    expect(memberDrops.single.name, 'Pick');
    expect(memberDrops.single.reason, contains('REJECT'));
  });

  test('source MATCH is ignored; final is the primary selector group', () {
    final clash = <String, Object?>{
      'proxies': [
        {
          'name': 'SS',
          'type': 'ss',
          'server': '1.2.3.4',
          'port': 8388,
          'cipher': 'aes-256-gcm',
          'password': 'password',
        },
      ],
      'proxy-groups': [
        {
          'name': 'Auto',
          'type': 'url-test',
          'proxies': ['SS'],
        },
        {
          'name': 'PROXY',
          'type': 'select',
          'proxies': ['SS'],
        },
      ],
      'rules': ['MATCH,Auto'],
    };
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final route = result.config['route'] as Map;
    expect(route['final'], 'PROXY');
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
    final dropped = _degradationsOf(
      result,
      SingBoxDegradationKind.groupDropped,
    );
    expect(dropped.map((d) => d.name), contains('Deny'));
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

  test('every reference in the clash sample resolves', () {
    final result = renderSingBoxFromClash(
      _clashSample(),
      secret: 'test-secret',
    );
    _expectAllReferencesResolve(result.config);
  });

  test('home broadband shape: unrenderable members never dangle', () {
    final result = renderSingBoxFromClash(
      _homeBroadbandShape(),
      secret: 'test-secret',
    );
    final outbounds = _outbounds(result.config);
    final tags = {for (final outbound in outbounds) outbound['tag']};
    expect(tags, isNot(contains('🏠 HK-家宽-01')));
    expect(tags, isNot(contains('🏠 家宽节点')));
    expect(tags, isNot(contains('🏠 家宽自动')));
    expect(tags, isNot(contains('🚀 节点选择')));
    final front = outbounds.firstWhere(
      (outbound) => outbound['tag'] == '⚡ CF前置',
    );
    expect(front['outbounds'], ['CF-01', 'CF-02']);
    final route = result.config['route'] as Map;
    expect(route['final'], '⚡ CF前置');
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.nodeProtocol,
      ).map((d) => d.name),
      containsAll(['🏠 HK-家宽-01', '🏠 JP-家宽-01']),
    );
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.groupType,
      ).map((d) => d.name),
      contains('🏠 家宽自动'),
    );
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.groupDropped,
      ).map((d) => d.name),
      contains('🏠 家宽节点'),
    );
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.groupMember,
      ).where((d) => d.name == '🏠 家宽节点').length,
      2,
    );
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.groupNested,
      ).map((d) => d.name),
      contains('🚀 节点选择'),
    );
    expect(_degradationsOf(result, SingBoxDegradationKind.routing).length, 1);
    _expectAllReferencesResolve(result.config);
  });

  test('nested groups degrade; member pruning drops hollow groups', () {
    final clash = _clashSample();
    (clash['proxies'] as List).add({
      'name': 'Ghost',
      'type': 'openvpn',
      'server': '6.6.6.6',
      'port': 1194,
    });
    (clash['proxy-groups'] as List).add({
      'name': 'Inner',
      'type': 'select',
      'proxies': ['Ghost'],
    });
    (clash['proxy-groups'] as List).add({
      'name': 'Outer',
      'type': 'select',
      'proxies': ['Inner'],
    });
    (clash['proxy-groups'] as List).add({
      'name': 'Top',
      'type': 'select',
      'proxies': ['Outer', 'SS'],
    });
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final outbounds = _outbounds(result.config);
    final tags = {for (final outbound in outbounds) outbound['tag']};
    expect(tags, isNot(contains('Inner')));
    expect(tags, isNot(contains('Outer')));
    expect(tags, isNot(contains('Top')));
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.groupDropped,
      ).map((d) => d.name),
      contains('Inner'),
    );
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.groupNested,
      ).map((d) => d.name),
      containsAll(['Outer', 'Top']),
    );
    _expectAllReferencesResolve(result.config);
  });

  test('dialer-proxy maps to a detour only when its target survives', () {
    final clash = _clashSample();
    (clash['proxies'] as List).add({
      'name': 'Chained',
      'type': 'vless',
      'server': '13.0.0.1',
      'port': 443,
      'uuid': '44444444-5555-6666-7777-888888888888',
      'dialer-proxy': 'PROXY',
    });
    (clash['proxies'] as List).add({
      'name': 'BadChain',
      'type': 'ss',
      'server': '13.0.0.2',
      'port': 8388,
      'cipher': 'aes-256-gcm',
      'password': 'password',
      'dialer-proxy': 'NoSuchGroup',
    });
    (clash['proxy-groups'] as List).add({
      'name': 'GroupChain',
      'type': 'select',
      'proxies': ['SS'],
      'dialer-proxy': 'PROXY',
    });
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final outbounds = _outbounds(result.config);
    final chained = outbounds.firstWhere(
      (outbound) => outbound['tag'] == 'Chained',
    );
    expect(chained['detour'], 'PROXY');
    final badChain = outbounds.firstWhere(
      (outbound) => outbound['tag'] == 'BadChain',
    );
    expect(badChain.containsKey('detour'), isFalse);
    final groupChain = outbounds.firstWhere(
      (outbound) => outbound['tag'] == 'GroupChain',
    );
    expect(groupChain.containsKey('detour'), isFalse);
    expect(
      _degradationsOf(result, SingBoxDegradationKind.chain).map((d) => d.name),
      containsAll(['BadChain', 'GroupChain']),
    );
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.chain,
      ).any((d) => d.name == 'Chained'),
      isFalse,
    );
    _expectAllReferencesResolve(result.config);
  });

  test(
    'a wireguard dialer-proxy reaches its endpoint detour or the ledger',
    () {
      final clash = _clashSample();
      Map<String, Object> wg(String name, String dialer) => {
        'name': name,
        'type': 'wireguard',
        'server': '5.5.5.5',
        'port': 51820,
        'ip': '10.0.0.2',
        'private-key': 'privatekey',
        'public-key': 'publickey',
        'dialer-proxy': dialer,
      };
      (clash['proxies'] as List).add(wg('WGChained', 'PROXY'));
      (clash['proxies'] as List).add(wg('WGBadChain', 'NoSuchGroup'));
      final result = renderSingBoxFromClash(clash, secret: 'test-secret');
      final endpoints = result.config['endpoints'] as List;
      final chained =
          endpoints.firstWhere((entry) => (entry as Map)['tag'] == 'WGChained')
              as Map;
      expect(chained['detour'], 'PROXY');
      final bad =
          endpoints.firstWhere((entry) => (entry as Map)['tag'] == 'WGBadChain')
              as Map;
      expect(bad.containsKey('detour'), isFalse);
      expect(
        _degradationsOf(
          result,
          SingBoxDegradationKind.chain,
        ).map((d) => d.name),
        contains('WGBadChain'),
      );
      _expectAllReferencesResolve(result.config);
    },
  );

  test('mutually referencing groups degrade; no cycle can be rendered', () {
    final clash = _clashSample();
    (clash['proxy-groups'] as List).add({
      'name': 'CycleA',
      'type': 'select',
      'proxies': ['CycleB', 'SS'],
    });
    (clash['proxy-groups'] as List).add({
      'name': 'CycleB',
      'type': 'select',
      'proxies': ['CycleA'],
    });
    (clash['proxy-groups'] as List).add({
      'name': 'SelfRef',
      'type': 'select',
      'proxies': ['SelfRef', 'SS'],
    });
    final result = renderSingBoxFromClash(clash, secret: 'test-secret');
    final outbounds = _outbounds(result.config);
    final tags = {for (final outbound in outbounds) outbound['tag']};
    expect(tags, isNot(contains('CycleA')));
    expect(tags, isNot(contains('CycleB')));
    expect(tags, isNot(contains('SelfRef')));
    expect(
      _degradationsOf(
        result,
        SingBoxDegradationKind.groupNested,
      ).map((d) => d.name),
      containsAll(['CycleA', 'CycleB', 'SelfRef']),
    );
    // No emitted outbound may list another outbound as a member, so the
    // member graph is a star over leaves and a cycle cannot exist.
    for (final outbound in outbounds) {
      final members = outbound['outbounds'];
      if (members is List) {
        for (final member in members) {
          final target = outbounds.firstWhere(
            (entry) => entry['tag'] == member,
          );
          expect(target.containsKey('outbounds'), isFalse, reason: '$member');
        }
      }
    }
    _expectAllReferencesResolve(result.config);
  });

  test('degradation ledger serializes to a stable json shape', () {
    final result = renderSingBoxFromClash(
      _homeBroadbandShape(),
      secret: 'test-secret',
    );
    final decoded =
        jsonDecode(
              jsonEncode([
                for (final degradation in result.degradations)
                  degradation.toJson(),
              ]),
            )
            as List;
    expect(decoded.length, result.degradations.length);
    final kindNames = SingBoxDegradationKind.values.map((k) => k.name).toSet();
    for (final entry in decoded) {
      final map = entry as Map;
      expect(map.keys.toSet(), {'kind', 'name', 'reason'});
      expect(kindNames, contains(map['kind']));
      expect((map['name'] as String).isNotEmpty, isTrue);
      expect((map['reason'] as String).isNotEmpty, isTrue);
    }
    expect(result.unsupported.length, result.degradations.length);
  });
}

/// The CFDirect shape behind the v0.2.27 phone failure: VPNGate home
/// broadband nodes are Clash `openvpn` proxies, which sing-box cannot
/// represent, chained through a vless front group via dialer-proxy.
Map<String, Object?> _homeBroadbandShape() {
  Map<String, Object?> openVpn(String name, String server) => {
    'name': name,
    'type': 'openvpn',
    'server': server,
    'port': 1194,
    'proto': 'tcp',
    'username': 'vpn',
    'password': 'vpn',
    'cipher': 'AES-128-CBC',
    'auth': 'SHA1',
    'udp': false,
    'dialer-proxy': '⚡ CF前置',
    'ca': 'CA-PEM',
    'cert': 'CERT-PEM',
    'key': 'KEY-PEM',
  };
  Map<String, Object?> vless(String name, String server) => {
    'name': name,
    'type': 'vless',
    'server': server,
    'port': 443,
    'uuid': '11111111-2222-3333-4444-555555555555',
    'tls': true,
    'servername': 'example.com',
    'network': 'ws',
    'ws-opts': {
      'path': '/ws',
      'headers': {'Host': 'example.com'},
    },
  };
  return {
    'proxies': [
      vless('CF-01', '104.16.0.1'),
      vless('CF-02', '104.17.0.1'),
      openVpn('🏠 HK-家宽-01', '219.100.37.1'),
      openVpn('🏠 JP-家宽-01', '219.100.37.2'),
    ],
    'proxy-groups': [
      {
        'name': '⚡ CF前置',
        'type': 'url-test',
        'proxies': ['CF-01', 'CF-02'],
        'url': 'https://www.gstatic.com/generate_204',
        'interval': 300,
        'tolerance': 50,
      },
      {
        'name': '🏠 家宽自动',
        'type': 'fallback',
        'proxies': ['🏠 HK-家宽-01', '🏠 JP-家宽-01'],
        'url': 'https://www.gstatic.com/generate_204',
        'interval': 1800,
        'lazy': true,
      },
      {
        'name': '🏠 家宽节点',
        'type': 'select',
        'proxies': ['🏠 HK-家宽-01', '🏠 JP-家宽-01'],
      },
      {
        'name': '🚀 节点选择',
        'type': 'select',
        'proxies': ['⚡ CF前置', '🏠 家宽自动', '🏠 家宽节点', 'CF-01'],
      },
    ],
    'rules': ['MATCH,🚀 节点选择'],
  };
}

/// Independent walk of every cross-reference in a rendered config;
/// `sing-box check` resolves none of these, so the tests must.
void _expectAllReferencesResolve(Map<String, Object?> config) {
  final outbounds = _outbounds(config);
  final tags = {for (final outbound in outbounds) outbound['tag'].toString()};
  final endpoints = config['endpoints'];
  if (endpoints is List) {
    for (final entry in endpoints) {
      tags.add((entry as Map)['tag'].toString());
    }
  }
  final route = config['route'] as Map;
  final ruleSetTags = {
    for (final def in route['rule_set'] as List) (def as Map)['tag'].toString(),
  };
  for (final outbound in outbounds) {
    final members = outbound['outbounds'];
    if (members is List) {
      for (final member in members) {
        expect(
          tags,
          contains(member.toString()),
          reason: 'member of ${outbound['tag']}',
        );
      }
    }
    final detour = outbound['detour'];
    if (detour != null) {
      expect(tags, contains(detour.toString()), reason: 'detour');
    }
  }
  for (final entry in route['rules'] as List) {
    final rule = entry as Map;
    final target = rule['outbound'];
    if (target != null) {
      expect(tags, contains(target.toString()), reason: 'rule target');
    }
    final sets = rule['rule_set'];
    if (sets is List) {
      for (final ref in sets) {
        expect(ruleSetTags, contains(ref.toString()), reason: 'rule_set');
      }
    }
  }
  expect(tags, contains(route['final'].toString()), reason: 'route final');
  final dns = config['dns'] as Map;
  final serverTags = {
    for (final server in dns['servers'] as List)
      (server as Map)['tag'].toString(),
  };
  for (final server in dns['servers'] as List) {
    final detour = (server as Map)['detour'];
    if (detour != null) {
      expect(tags, contains(detour.toString()), reason: 'dns detour');
    }
  }
  expect(serverTags, contains(dns['final'].toString()), reason: 'dns final');
}
