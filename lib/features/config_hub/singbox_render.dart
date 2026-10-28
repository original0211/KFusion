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
    default:
      return target;
  }
}

/// Registers a remote rule set for a Clash GEOIP/GEOSITE [code] in
/// [ruleSets]; sing-box 1.12 removed the geoip/geosite rule fields.
String _registerGeoRuleSet(
  Map<String, Map<String, Object?>> ruleSets,
  String kind,
  String code,
) {
  final tag = '$kind-${code.toLowerCase()}';
  ruleSets.putIfAbsent(
    tag,
    () => {
      'type': 'remote',
      'tag': tag,
      'format': 'binary',
      'url':
          'https://raw.githubusercontent.com/SagerNet/sing-$kind/'
          'rule-set/$tag.srs',
      'download_detour': 'direct',
    },
  );
  return tag;
}

Map<String, Object?> _tlsFromClash(Map<String, Object?> params) {
  if (params['tls'] != true) return const {};
  final tls = <String, Object?>{'enabled': true};
  final servername = params['servername'] ?? params['sni'];
  if (servername != null) tls['server_name'] = servername;
  if (params['skip-cert-verify'] == true) tls['insecure'] = true;
  if (params['alpn'] != null) tls['alpn'] = params['alpn'];
  final reality = _asMap(params['reality-opts']);
  final fingerprint = params['fingerprint'];
  if (fingerprint != null) {
    tls['utls'] = {'enabled': true, 'fingerprint': fingerprint};
  } else if (reality.isNotEmpty) {
    // sing-box requires uTLS for reality clients; mihomo defaults to chrome.
    tls['utls'] = {'enabled': true, 'fingerprint': 'chrome'};
  }
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

/// Renders a Clash wireguard node as a sing-box endpoint.
Map<String, Object?>? _wireGuardEndpoint(
  IrNode node,
  List<String> unsupported,
) {
  final params = node.params;
  final ip = _asString(params['ip']);
  final ipv6 = _asString(params['ipv6']);
  final addresses = [
    if (ip.isNotEmpty) '$ip/32',
    if (ipv6.isNotEmpty) '$ipv6/128',
  ];
  if (addresses.isEmpty) {
    unsupported.add(
      'wireguard node "${node.name}" has no local address (ip/ipv6)',
    );
    return null;
  }
  return {
    'type': 'wireguard',
    'tag': node.name,
    'address': addresses,
    if (params['private-key'] != null) 'private_key': params['private-key'],
    if (params['mtu'] != null) 'mtu': params['mtu'],
    'peers': [
      {
        'address': node.server,
        'port': node.port,
        if (params['public-key'] != null) 'public_key': params['public-key'],
        if (params['preshared-key'] != null)
          'pre_shared_key': params['preshared-key'],
        'allowed_ips': ['0.0.0.0/0', '::/0'],
        if (params['reserved'] != null) 'reserved': params['reserved'],
      },
    ],
  };
}

Map<String, Object?>? _groupToSingBox(
  Map<String, Object?> group,
  List<String> unsupported,
) {
  final name = _asString(group['name']);
  final type = _asString(group['type']);
  final proxies = <String>[];
  for (final entry in _asList(group['proxies'])) {
    final member = entry.toString();
    if (member == 'REJECT') {
      unsupported.add(
        'REJECT in proxy-group "$name" (no block outbound in sing-box 1.13+)',
      );
      continue;
    }
    proxies.add(_target(member));
  }
  if (proxies.isEmpty) {
    unsupported.add('proxy-group "$name" has no usable member');
    return null;
  }
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

List<Map<String, Object?>> _rulesToSingBox(
  String line,
  List<String> unsupported,
  Map<String, Map<String, Object?>> ruleSets,
) {
  var parts = line.split(',');
  if (parts.length < 2) {
    unsupported.add('rule "$line"');
    return const [];
  }
  if (parts.last.trim() == 'no-resolve') {
    parts = parts.sublist(0, parts.length - 1);
  }
  final kind = parts.first.trim();
  final rawTarget = parts.last.trim();
  final args = parts.sublist(1, parts.length - 1).map((e) => e.trim()).toList();
  final List<Map<String, Object?>> rules;
  switch (kind) {
    case 'DOMAIN':
      rules = [
        {'domain': args},
      ];
    case 'DOMAIN-SUFFIX':
      rules = [
        {'domain_suffix': args},
      ];
    case 'DOMAIN-KEYWORD':
      rules = [
        {'domain_keyword': args},
      ];
    case 'DOMAIN-REGEX':
      rules = [
        {'domain_regex': args},
      ];
    case 'IP-CIDR':
    case 'IP-CIDR6':
      rules = [
        {'ip_cidr': args},
      ];
    case 'SRC-IP-CIDR':
      rules = [
        {'source_ip_cidr': args},
      ];
    case 'SRC-PORT':
      rules = [_portRuleFields(args, 'source_port', 'source_port_range')];
    case 'DST-PORT':
      rules = [_portRuleFields(args, 'port', 'port_range')];
    case 'GEOIP':
      final codes = args.where((arg) => arg != 'no-resolve').toList();
      if (codes.isEmpty) {
        unsupported.add('rule "$line"');
        return const [];
      }
      // sing-geoip publishes country codes only: the LAN code has no
      // upstream file (its URL 404s), so it takes the native field instead.
      final remoteCodes = [
        for (final code in codes)
          if (code.toUpperCase() != 'LAN') code,
      ];
      rules = [
        if (remoteCodes.isNotEmpty)
          {
            'rule_set': [
              for (final code in remoteCodes)
                _registerGeoRuleSet(ruleSets, 'geoip', code),
            ],
          },
        if (remoteCodes.length != codes.length) {'ip_is_private': true},
      ];
    case 'GEOSITE':
      if (args.isEmpty) {
        unsupported.add('rule "$line"');
        return const [];
      }
      rules = [
        {
          'rule_set': [
            for (final code in args)
              _registerGeoRuleSet(ruleSets, 'geosite', code),
          ],
        },
      ];
    case 'PROCESS-NAME':
      rules = [
        {'process_name': args},
      ];
    default:
      unsupported.add('rule "$line"');
      return const [];
  }
  // A REJECT target becomes the rule action; no outbound represents it.
  for (final rule in rules) {
    if (rawTarget == 'REJECT') {
      rule['action'] = 'reject';
    } else {
      rule['outbound'] = _target(rawTarget);
    }
  }
  return rules;
}

Map<String, Object?> _portRuleFields(
  List<String> args,
  String singleKey,
  String rangeKey,
) {
  final rule = <String, Object?>{};
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
  final endpoints = <Map<String, Object?>>[];
  final nodeByName = <String, IrNode>{};
  final leafTags = <String>{'direct'};
  final leafOrder = <String>[];
  for (final node in profile.nodes) {
    nodeByName[node.name] = node;
    if (node.type == 'wireguard') {
      final endpoint = _wireGuardEndpoint(node, unsupported);
      if (endpoint != null) {
        endpoints.add(endpoint);
        leafTags.add(node.name);
        leafOrder.add(node.name);
      }
      continue;
    }
    final outbound = _nodeToSingBox(node, unsupported);
    if (outbound != null) {
      outbounds.add(outbound);
      leafTags.add(node.name);
      leafOrder.add(node.name);
    }
  }
  final groupCandidates = <Map<String, Object?>>[];
  final groupByName = <String, Map<String, Object?>>{};
  for (final group in profile.groups) {
    groupByName[_asString(group['name'])] = group;
    final outbound = _groupToSingBox(group, unsupported);
    if (outbound != null) groupCandidates.add(outbound);
  }
  // Group members are copied verbatim from the Clash config, so a member
  // whose node produced no outbound would dangle until start resolves it.
  final groupNames = _pruneGroupMembers(groupCandidates, leafTags, unsupported);
  outbounds.addAll(groupCandidates);
  final allTags = <String>{...leafTags, ...groupNames};
  _applyDialerDetours(outbounds, nodeByName, groupByName, allTags, unsupported);
  outbounds.add(const {'type': 'direct', 'tag': 'direct'});
  final ruleSets = <String, Map<String, Object?>>{};
  final dnsRuleSet = _registerGeoRuleSet(ruleSets, 'geosite', 'cn');
  final rules = <Map<String, Object?>>[
    {'protocol': 'dns', 'action': 'hijack-dns'},
  ];
  var finalOutbound = '';
  var finalRejected = false;
  for (final line in profile.rules) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final kind = trimmed.split(',').first.trim();
    if (kind == 'MATCH' || kind == 'FINAL') {
      final target = trimmed.split(',').last.trim();
      if (target == 'REJECT') {
        finalRejected = true;
      } else {
        finalOutbound = _target(target);
      }
      continue;
    }
    for (final rule in _rulesToSingBox(trimmed, unsupported, ruleSets)) {
      final target = rule['outbound'];
      if (target != null && !allTags.contains(target)) {
        unsupported.add(
          'rule "$trimmed" target "$target" has no sing-box outbound',
        );
        continue;
      }
      rules.add(rule);
    }
  }
  if (finalRejected) {
    rules.add({'action': 'reject'});
  }
  if (finalOutbound.isNotEmpty && !allTags.contains(finalOutbound)) {
    unsupported.add('MATCH target "$finalOutbound" has no sing-box outbound');
    finalOutbound = '';
  }
  if (finalOutbound.isEmpty) {
    if (groupNames.isNotEmpty) {
      finalOutbound = groupNames.first;
    } else if (leafOrder.isNotEmpty) {
      finalOutbound = leafOrder.first;
    } else {
      finalOutbound = 'direct';
    }
  }
  final proxyOutbound = groupNames.isNotEmpty
      ? groupNames.first
      : leafOrder.isNotEmpty
      ? leafOrder.first
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
      'address': ['172.19.0.1/30'],
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
          'type': 'https',
          'tag': 'remote',
          'server': 'dns.google',
          'path': '/dns-query',
          'detour': proxyOutbound,
        },
        {'type': 'udp', 'tag': 'direct', 'server': '223.5.5.5'},
        {
          'type': 'fakeip',
          'tag': 'fakeip',
          'inet4_range': '198.18.0.0/15',
          'inet6_range': 'fc00::/18',
        },
      ],
      'rules': [
        {
          'rule_set': [dnsRuleSet],
          'server': 'direct',
        },
        {
          'query_type': ['A', 'AAAA'],
          'server': 'fakeip',
        },
      ],
      'final': 'remote',
      'strategy': 'prefer_ipv4',
    },
    'inbounds': inbounds,
    'outbounds': outbounds,
    if (endpoints.isNotEmpty) 'endpoints': endpoints,
    'route': {
      'rules': rules,
      if (ruleSets.isNotEmpty) 'rule_set': ruleSets.values.toList(),
      'final': finalOutbound,
      'auto_detect_interface': true,
      'default_domain_resolver': {'server': 'direct'},
    },
    'experimental': {
      'clash_api': {
        'external_controller': '127.0.0.1:$clashApiPort',
        'secret': secret,
        'default_mode': 'rule',
      },
      'cache_file': {'enabled': true, 'path': 'cache.db'},
    },
  };
  final unresolved = _unresolvedSingBoxReferences(config);
  if (unresolved.isNotEmpty) {
    throw StateError(
      'sing-box render left unresolvable references: '
      '${unresolved.join('; ')}',
    );
  }
  return SingBoxRenderResult(config: config, unsupported: unsupported);
}

/// Drops group members no emitted outbound or endpoint carries, then
/// drops groups left with no resolvable member; both cascade.
List<String> _pruneGroupMembers(
  List<Map<String, Object?>> candidates,
  Set<String> leafTags,
  List<String> unsupported,
) {
  final alive = <String>{
    for (final candidate in candidates) candidate['tag'].toString(),
  };
  var changed = true;
  while (changed) {
    changed = false;
    for (final candidate in candidates) {
      final tag = candidate['tag'].toString();
      if (!alive.contains(tag)) continue;
      final resolvable = _asList(
        candidate['outbounds'],
      ).any((member) => leafTags.contains(member) || alive.contains(member));
      if (!resolvable) {
        alive.remove(tag);
        changed = true;
      }
    }
  }
  candidates.removeWhere((candidate) {
    final tag = candidate['tag'].toString();
    if (alive.contains(tag)) return false;
    unsupported.add(
      'proxy-group "$tag" dropped: no member resolves to a sing-box '
      'outbound',
    );
    return true;
  });
  final surviving = <String>[];
  for (final candidate in candidates) {
    final tag = candidate['tag'].toString();
    surviving.add(tag);
    final kept = <Object?>[];
    for (final member in _asList(candidate['outbounds'])) {
      if (leafTags.contains(member) || alive.contains(member)) {
        kept.add(member);
      } else {
        unsupported.add(
          'proxy-group "$tag" member "$member" has no sing-box outbound',
        );
      }
    }
    candidate['outbounds'] = kept;
  }
  return surviving;
}

/// Maps a Clash `dialer-proxy` onto the sing-box `detour` of the outbound
/// it chains through; group outbounds have no detour field in sing-box.
void _applyDialerDetours(
  List<Map<String, Object?>> outbounds,
  Map<String, IrNode> nodeByName,
  Map<String, Map<String, Object?>> groupByName,
  Set<String> allTags,
  List<String> unsupported,
) {
  for (final outbound in outbounds) {
    final tag = outbound['tag'].toString();
    final node = nodeByName[tag];
    final Object? dialer = node != null
        ? node.params['dialer-proxy']
        : groupByName[tag]?['dialer-proxy'];
    if (dialer is! String || dialer.isEmpty) continue;
    if (node == null) {
      unsupported.add(
        'dialer-proxy on proxy-group "$tag" is not supported in sing-box',
      );
      continue;
    }
    final target = _target(dialer);
    if (allTags.contains(target)) {
      outbound['detour'] = target;
    } else {
      unsupported.add(
        'dialer-proxy "$dialer" of "$tag" has no sing-box outbound',
      );
    }
  }
}

/// Every cross-reference a rendered config carries, each in its own
/// namespace; `sing-box check` resolves none of these, only start does.
List<String> _unresolvedSingBoxReferences(Map<String, Object?> config) {
  final problems = <String>[];
  final outboundTags = <String>{};
  final outbounds = <Map<String, Object?>>[];
  for (final entry in _asList(config['outbounds'])) {
    final outbound = _asMap(entry);
    outbounds.add(outbound);
    outboundTags.add(_asString(outbound['tag']));
  }
  for (final entry in _asList(config['endpoints'])) {
    outboundTags.add(_asString(_asMap(entry)['tag']));
  }
  void checkRef(String kind, Object? ref, Set<String> namespace) {
    if (ref == null) return;
    if (!namespace.contains(ref.toString())) {
      problems.add('$kind "$ref"');
    }
  }

  final route = _asMap(config['route']);
  final ruleSetTags = <String>{
    for (final entry in _asList(route['rule_set']))
      _asString(_asMap(entry)['tag']),
  };
  for (final outbound in outbounds) {
    for (final member in _asList(outbound['outbounds'])) {
      checkRef('member of "${outbound['tag']}"', member, outboundTags);
    }
    checkRef(
      'detour of "${outbound['tag']}"',
      outbound['detour'],
      outboundTags,
    );
  }
  for (final entry in _asList(route['rules'])) {
    final rule = _asMap(entry);
    checkRef('rule outbound', rule['outbound'], outboundTags);
    for (final ref in _asList(rule['rule_set'])) {
      checkRef('rule rule_set', ref, ruleSetTags);
    }
  }
  checkRef('route final', route['final'], outboundTags);
  for (final entry in _asList(route['rule_set'])) {
    checkRef(
      'rule_set download_detour',
      _asMap(entry)['download_detour'],
      outboundTags,
    );
  }
  final dns = _asMap(config['dns']);
  final dnsServerTags = <String>{};
  for (final entry in _asList(dns['servers'])) {
    final server = _asMap(entry);
    dnsServerTags.add(_asString(server['tag']));
    checkRef('dns server detour', server['detour'], outboundTags);
  }
  for (final entry in _asList(dns['rules'])) {
    final rule = _asMap(entry);
    checkRef('dns rule server', rule['server'], dnsServerTags);
    for (final ref in _asList(rule['rule_set'])) {
      checkRef('dns rule rule_set', ref, ruleSetTags);
    }
  }
  checkRef('dns final', dns['final'], dnsServerTags);
  checkRef(
    'default_domain_resolver',
    _asMap(route['default_domain_resolver'])['server'],
    dnsServerTags,
  );
  return problems;
}
