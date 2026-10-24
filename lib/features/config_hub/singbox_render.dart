import 'package:kfusion/features/config_hub/ir.dart';

class SingBoxRenderResult {
  const SingBoxRenderResult({
    required this.config,
    this.unsupported = const [],
  });

  final Map<String, Object?> config;
  final List<String> unsupported;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return {
      for (final MapEntry(:key, :value) in value.entries) key.toString(): value,
    };
  }
  return const {};
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}

String _asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

int _asPort(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

String _target(String target) {
  switch (target) {
    case 'DIRECT':
      return 'direct';
    case 'REJECT':
      return 'block';
    default:
      return target;
  }
}

Map<String, Object?> _tlsFromClash(Map<String, Object?> params) {
  if (params['tls'] != true) return const {};
  final tls = <String, Object?>{'enabled': true};
  final servername = params['servername'] ?? params['sni'];
  if (servername != null) tls['server_name'] = servername;
  if (params['skip-cert-verify'] == true) tls['insecure'] = true;
  if (params['alpn'] != null) tls['alpn'] = params['alpn'];
  final fingerprint = params['fingerprint'];
  if (fingerprint != null) {
    tls['utls'] = {'enabled': true, 'fingerprint': fingerprint};
  }
  final reality = _asMap(params['reality-opts']);
  if (reality.isNotEmpty) {
    tls['reality'] = {
      'enabled': true,
      if (reality['public-key'] != null) 'public_key': reality['public-key'],
      if (reality['short-id'] != null) 'short_id': reality['short-id'],
    };
  }
  return tls;
}

Map<String, Object?> _transportFromClash(Map<String, Object?> params) {
  final network = _asString(params['network']);
  switch (network) {
    case 'ws':
      final opts = _asMap(params['ws-opts']);
      return {
        'type': 'ws',
        if (opts['path'] != null) 'path': opts['path'],
        if (opts['headers'] != null) 'headers': opts['headers'],
      };
    case 'grpc':
      final opts = _asMap(params['grpc-opts']);
      return {
        'type': 'grpc',
        if (opts['grpc-service-name'] != null)
          'service_name': opts['grpc-service-name'],
      };
    case 'http':
      final opts = _asMap(params['http-opts']);
      return {
        'type': 'http',
        if (opts['path'] != null) 'path': opts['path'],
        if (opts['headers'] != null) 'headers': opts['headers'],
      };
    case 'h2':
      final opts = _asMap(params['h2-opts']);
      return {
        'type': 'http',
        if (opts['host'] != null) 'host': opts['host'],
        if (opts['path'] != null) 'path': opts['path'],
      };
    default:
      return const {};
  }
}

Map<String, Object?>? _nodeToSingBox(IrNode node, List<String> unsupported) {
  final params = node.params;
  final base = <String, Object?>{
    'tag': node.name,
    'server': node.server,
    'server_port': node.port,
  };
  final tls = _tlsFromClash(params);
  final transport = _transportFromClash(params);
  switch (node.type) {
    case 'ss':
      return {
        ...base,
        'type': 'shadowsocks',
        if (params['cipher'] != null) 'method': params['cipher'],
        if (params['password'] != null) 'password': params['password'],
      };
    case 'vmess':
      return {
        ...base,
        'type': 'vmess',
        if (params['uuid'] != null) 'uuid': params['uuid'],
        if (params['cipher'] != null) 'security': params['cipher'],
        if (params['alterId'] != null) 'alter_id': params['alterId'],
        if (transport.isNotEmpty) 'transport': transport,
        if (tls.isNotEmpty) 'tls': tls,
      };
    case 'vless':
      return {
        ...base,
        'type': 'vless',
        if (params['uuid'] != null) 'uuid': params['uuid'],
        if (params['flow'] != null) 'flow': params['flow'],
        if (transport.isNotEmpty) 'transport': transport,
        if (tls.isNotEmpty) 'tls': tls,
      };
    case 'trojan':
      return {
        ...base,
        'type': 'trojan',
        if (params['password'] != null) 'password': params['password'],
        if (transport.isNotEmpty) 'transport': transport,
        if (tls.isNotEmpty) 'tls': tls,
      };
    case 'hysteria2':
      final obfsTls = <String, Object?>{'enabled': true};
      final sni = params['sni'];
      if (sni != null) obfsTls['server_name'] = sni;
      if (params['skip-cert-verify'] == true) obfsTls['insecure'] = true;
      if (params['alpn'] != null) obfsTls['alpn'] = params['alpn'];
      return {
        ...base,
        'type': 'hysteria2',
        if (params['password'] != null) 'password': params['password'],
        if (params['obfs'] != null)
          'obfs': {
            'type': params['obfs'],
            if (params['obfs-password'] != null)
              'password': params['obfs-password'],
          },
        'tls': obfsTls,
      };
    case 'tuic':
      return {
        ...base,
        'type': 'tuic',
        if (params['uuid'] != null) 'uuid': params['uuid'],
        if (params['password'] != null) 'password': params['password'],
        if (params['congestion-controller'] != null)
          'congestion_control': params['congestion-controller'],
        if (params['udp-relay-mode'] != null)
          'udp_relay_mode': params['udp-relay-mode'],
        'tls': {
          'enabled': true,
          if (params['sni'] != null) 'server_name': params['sni'],
          if (params['alpn'] != null) 'alpn': params['alpn'],
        },
      };
    case 'wireguard':
      final ip = _asString(params['ip']);
      final ipv6 = _asString(params['ipv6']);
      final local = ip.isNotEmpty
          ? '$ip/32'
          : ipv6.isNotEmpty
          ? '$ipv6/128'
          : '';
      return {
        ...base,
        'type': 'wireguard',
        if (local.isNotEmpty) 'local_address': [local],
        if (params['private-key'] != null) 'private_key': params['private-key'],
        if (params['public-key'] != null)
          'peer_public_key': params['public-key'],
        if (params['preshared-key'] != null)
          'pre_shared_key': params['preshared-key'],
        if (params['reserved'] != null) 'reserved': params['reserved'],
        'peers': [
          {
            'address': '${node.server}:${node.port}',
            if (params['public-key'] != null)
              'public_key': params['public-key'],
            if (params['preshared-key'] != null)
              'pre_shared_key': params['preshared-key'],
            'allowed_ips': ['0.0.0.0/0', '::/0'],
            if (params['reserved'] != null) 'reserved': params['reserved'],
          },
        ],
      };
    case 'socks5':
      return {
        ...base,
        'type': 'socks',
        'version': '5',
        if (params['username'] != null) 'username': params['username'],
        if (params['password'] != null) 'password': params['password'],
      };
    case 'http':
      return {
        ...base,
        'type': 'http',
        if (params['username'] != null) 'username': params['username'],
        if (params['password'] != null) 'password': params['password'],
      };
    default:
      unsupported.add('proxy type "${node.type}" (${node.name})');
      return null;
  }
}

Map<String, Object?>? _groupToSingBox(
  Map<String, Object?> group,
  List<String> unsupported,
) {
  final name = _asString(group['name']);
  final type = _asString(group['type']);
  final proxies = [
    for (final entry in _asList(group['proxies'])) entry.toString(),
  ];
  switch (type) {
    case 'select':
      return {'type': 'selector', 'tag': name, 'outbounds': proxies};
    case 'url-test':
      return {
        'type': 'urltest',
        'tag': name,
        'outbounds': proxies,
        'url': _asString(group['url'], 'https://www.gstatic.com/generate_204'),
        if (group['interval'] != null)
          'interval': _intervalText(group['interval']),
        if (group['tolerance'] != null) 'tolerance': group['tolerance'],
      };
    default:
      unsupported.add('proxy-group type "$type" ($name)');
      return null;
  }
}

String _intervalText(Object? value) {
  if (value is int) return '${value}s';
  if (value is num) return '${value.toInt()}s';
  final text = value.toString();
  if (RegExp(r'^\d+$').hasMatch(text)) return '${text}s';
  return text;
}

Map<String, Object?>? _ruleToSingBox(String line, List<String> unsupported) {
  var parts = line.split(',');
  if (parts.length < 2) {
    unsupported.add('rule "$line"');
    return null;
  }
  if (parts.last.trim() == 'no-resolve') {
    parts = parts.sublist(0, parts.length - 1);
  }
  final kind = parts.first.trim();
  final target = _target(parts.last.trim());
  final args = parts.sublist(1, parts.length - 1).map((e) => e.trim()).toList();
  switch (kind) {
    case 'DOMAIN':
      return {'domain': args, 'outbound': target};
    case 'DOMAIN-SUFFIX':
      return {'domain_suffix': args, 'outbound': target};
    case 'DOMAIN-KEYWORD':
      return {'domain_keyword': args, 'outbound': target};
    case 'DOMAIN-REGEX':
      return {'domain_regex': args, 'outbound': target};
    case 'IP-CIDR':
    case 'IP-CIDR6':
      return {'ip_cidr': args, 'outbound': target};
    case 'SRC-IP-CIDR':
      return {'source_ip_cidr': args, 'outbound': target};
    case 'SRC-PORT':
      return _portRule(args, target, 'source_port', 'source_port_range');
    case 'DST-PORT':
      return _portRule(args, target, 'port', 'port_range');
    case 'GEOIP':
      final codes = args.where((arg) => arg != 'no-resolve').toList();
      return {'geoip': codes, 'outbound': target};
    case 'GEOSITE':
      return {'geosite': args, 'outbound': target};
    case 'PROCESS-NAME':
      return {'process_name': args, 'outbound': target};
    default:
      unsupported.add('rule "$line"');
      return null;
  }
}

Map<String, Object?> _portRule(
  List<String> args,
  String target,
  String singleKey,
  String rangeKey,
) {
  final rule = <String, Object?>{'outbound': target};
  final singles = <int>[];
  final ranges = <String>[];
  for (final arg in args) {
    if (arg.contains('-')) {
      ranges.add(arg);
    } else {
      final port = int.tryParse(arg);
      if (port != null) singles.add(port);
    }
  }
  if (singles.isNotEmpty) rule[singleKey] = singles;
  if (ranges.isNotEmpty) rule[rangeKey] = ranges;
  return rule;
}

IrProfile _irFromClashMap(Map<String, Object?> doc) {
  final nodes = <IrNode>[];
  for (final entry in _asList(doc['proxies'])) {
    final node = _asMap(entry);
    final name = _asString(node['name']);
    if (name.isEmpty) continue;
    nodes.add(
      IrNode(
        name: name,
        type: _asString(node['type']),
        server: _asString(node['server']),
        port: _asPort(node['port']),
        params: {
          for (final MapEntry(:key, :value) in node.entries)
            if (key != 'name' &&
                key != 'type' &&
                key != 'server' &&
                key != 'port')
              key: value,
        },
      ),
    );
  }
  return IrProfile(
    nodes: nodes,
    groups: [for (final entry in _asList(doc['proxy-groups'])) _asMap(entry)],
    rules: [for (final entry in _asList(doc['rules'])) entry.toString()],
  );
}

SingBoxRenderResult renderSingBoxFromClash(
  Map<String, Object?> clash, {
  required String secret,
  bool tunEnabled = false,
  int clashApiPort = 9091,
  int mixedPort = 7890,
}) {
  return renderSingBox(
    _irFromClashMap(clash),
    secret: secret,
    tunEnabled: tunEnabled,
    clashApiPort: clashApiPort,
    mixedPort: mixedPort,
  );
}

SingBoxRenderResult renderSingBox(
  IrProfile profile, {
  required String secret,
  bool tunEnabled = false,
  int clashApiPort = 9091,
  int mixedPort = 7890,
}) {
  final unsupported = <String>[];
  final outbounds = <Map<String, Object?>>[];
  for (final node in profile.nodes) {
    final outbound = _nodeToSingBox(node, unsupported);
    if (outbound != null) outbounds.add(outbound);
  }
  final groupNames = <String>[];
  for (final group in profile.groups) {
    final outbound = _groupToSingBox(group, unsupported);
    if (outbound != null) {
      outbounds.add(outbound);
      groupNames.add(_asString(group['name']));
    }
  }
  outbounds.addAll(const [
    {'type': 'direct', 'tag': 'direct'},
    {'type': 'block', 'tag': 'block'},
    {'type': 'dns', 'tag': 'dns'},
  ]);
  final rules = <Map<String, Object?>>[];
  var finalOutbound = '';
  for (final line in profile.rules) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final kind = trimmed.split(',').first.trim();
    if (kind == 'MATCH' || kind == 'FINAL') {
      final target = trimmed.split(',').last.trim();
      finalOutbound = _target(target);
      continue;
    }
    final rule = _ruleToSingBox(trimmed, unsupported);
    if (rule != null) rules.add(rule);
  }
  if (finalOutbound.isEmpty) {
    if (groupNames.isNotEmpty) {
      finalOutbound = groupNames.first;
    } else if (profile.nodes.isNotEmpty) {
      finalOutbound = profile.nodes.first.name;
    } else {
      finalOutbound = 'direct';
    }
  }
  final proxyOutbound = groupNames.isNotEmpty
      ? groupNames.first
      : profile.nodes.isNotEmpty
      ? profile.nodes.first.name
      : 'direct';
  final inbounds = <Map<String, Object?>>[
    {
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': '127.0.0.1',
      'listen_port': mixedPort,
    },
  ];
  if (tunEnabled) {
    inbounds.add({
      'type': 'tun',
      'tag': 'tun-in',
      'interface_name': 'kfusion-tun',
      'inet4_address': '172.19.0.1/30',
      'auto_route': true,
      'strict_route': true,
      'stack': 'system',
    });
  }
  final config = <String, Object?>{
    'log': {'level': 'info', 'timestamp': true},
    'dns': {
      'servers': [
        {
          'tag': 'remote',
          'address': 'https://dns.google/dns-query',
          'detour': proxyOutbound,
        },
        {'tag': 'direct', 'address': '223.5.5.5', 'detour': 'direct'},
      ],
      'rules': [
        {
          'geosite': ['cn'],
          'server': 'direct',
        },
      ],
      'final': 'remote',
      'strategy': 'prefer_ipv4',
      'fakeip': {
        'enabled': true,
        'inet4_range': '198.18.0.0/15',
        'inet6_range': 'fc00::/18',
      },
    },
    'inbounds': inbounds,
    'outbounds': outbounds,
    'route': {
      'rules': rules,
      'final': finalOutbound,
      'auto_detect_interface': true,
    },
    'experimental': {
      'clash_api': {
        'external_controller': '127.0.0.1:$clashApiPort',
        'secret': secret,
        'default_mode': 'rule',
        'store_selected': true,
        'cache_file': true,
      },
    },
  };
  return SingBoxRenderResult(config: config, unsupported: unsupported);
}
