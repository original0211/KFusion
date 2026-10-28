import 'package:kfusion/features/config_hub/ir.dart';

/// Why one piece of a Clash profile did not reach the sing-box render.
enum SingBoxDegradationKind {
  nodeProtocol,
  nodeUnusable,
  groupType,
  groupNested,
  groupDropped,
  groupMember,
  chain,
  routing,
}

/// One named item the render degraded; the render's single drop ledger.
class SingBoxDegradation {
  const SingBoxDegradation({
    required this.kind,
    required this.name,
    required this.reason,
    required this.message,
  });

  final SingBoxDegradationKind kind;
  final String name;
  final String reason;

  final String message;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'name': name,
    'reason': reason,
  };
}

class SingBoxRenderResult {
  const SingBoxRenderResult({
    required this.config,
    this.degradations = const [],
  });

  final Map<String, Object?> config;
  final List<SingBoxDegradation> degradations;

  List<String> get unsupported => [
    for (final degradation in degradations) degradation.message,
  ];
}

/// Clash node types the sing-box contract converts (SUBTRACTION_SPEC.md §2).
const singBoxContractNodeTypes = {
  'ss',
  'vmess',
  'vless',
  'trojan',
  'hysteria2',
  'tuic',
  'wireguard',
  'socks5',
  'http',
};

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

SingBoxDegradation _nodeProtocolDegradation(IrNode node) {
  return SingBoxDegradation(
    kind: SingBoxDegradationKind.nodeProtocol,
    name: node.name,
    reason: '协议 ${node.type} 不在 sing-box 渲染契约内',
    message: 'proxy type "${node.type}" (${node.name})',
  );
}

Map<String, Object?>? _nodeToSingBox(
  IrNode node,
  List<SingBoxDegradation> degradations,
) {
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
      degradations.add(_nodeProtocolDegradation(node));
      return null;
  }
}

/// Renders a Clash wireguard node as a sing-box endpoint.
Map<String, Object?>? _wireGuardEndpoint(
  IrNode node,
  List<SingBoxDegradation> degradations,
) {
  final params = node.params;
  final ip = _asString(params['ip']);
  final ipv6 = _asString(params['ipv6']);
  final addresses = [
    if (ip.isNotEmpty) '$ip/32',
    if (ipv6.isNotEmpty) '$ipv6/128',
  ];
  if (addresses.isEmpty) {
    degradations.add(
      SingBoxDegradation(
        kind: SingBoxDegradationKind.nodeUnusable,
        name: node.name,
        reason: 'wireguard 节点缺少本地地址（ip/ipv6）',
        message: 'wireguard node "${node.name}" has no local address (ip/ipv6)',
      ),
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
  Map<String, Object?> group, {
  required Set<String> leafTags,
  required Set<String> sourceGroupNames,
  required List<SingBoxDegradation> degradations,
}) {
  final name = _asString(group['name']);
  final type = _asString(group['type']);
  if (type != 'select' && type != 'url-test') {
    degradations.add(
      SingBoxDegradation(
        kind: SingBoxDegradationKind.groupType,
        name: name,
        reason: '组类型 $type 未承接（契约只保留 select / url-test）',
        message: 'proxy-group type "$type" ($name)',
      ),
    );
    return null;
  }
  final rawMembers = [
    for (final entry in _asList(group['proxies'])) entry.toString(),
  ];
  if (rawMembers.any(sourceGroupNames.contains)) {
    degradations.add(
      SingBoxDegradation(
        kind: SingBoxDegradationKind.groupNested,
        name: name,
        reason: '组成员包含其他组，嵌套组未承接',
        message: 'proxy-group "$name" nests other proxy-groups',
      ),
    );
    return null;
  }
  final members = <String>[];
  for (final member in rawMembers) {
    if (member == 'REJECT') {
      degradations.add(
        SingBoxDegradation(
          kind: SingBoxDegradationKind.groupMember,
          name: name,
          reason: 'REJECT 成员在 sing-box 1.13+ 无对应出站，已剪除',
          message:
              'REJECT in proxy-group "$name" (no block outbound in '
              'sing-box 1.13+)',
        ),
      );
      continue;
    }
    final tag = _target(member);
    if (leafTags.contains(tag)) {
      members.add(tag);
    } else {
      degradations.add(
        SingBoxDegradation(
          kind: SingBoxDegradationKind.groupMember,
          name: name,
          reason: '成员 $member 在 sing-box 下不可用，已剪除',
          message:
              'proxy-group "$name" member "$member" has no sing-box '
              'outbound',
        ),
      );
    }
  }
  if (members.isEmpty) {
    degradations.add(
      SingBoxDegradation(
        kind: SingBoxDegradationKind.groupDropped,
        name: name,
        reason: '组内成员全部不可用',
        message: 'proxy-group "$name" has no usable member',
      ),
    );
    return null;
  }
  switch (type) {
    case 'select':
      return {'type': 'selector', 'tag': name, 'outbounds': members};
    case 'url-test':
      return {
        'type': 'urltest',
        'tag': name,
        'outbounds': members,
        'url': _asString(group['url'], 'https://www.gstatic.com/generate_204'),
        if (group['interval'] != null)
          'interval': _intervalText(group['interval']),
        if (group['tolerance'] != null) 'tolerance': group['tolerance'],
      };
    default:
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

/// The built-in route template of the subtraction contract
/// (SUBTRACTION_SPEC.md §2): private and CN traffic direct, the rest to
/// the primary outbound. Both rule-set files were verified live (HTTP
/// 200) on 2026-10-28; sing-geoip publishes country codes only, so no
/// LAN set exists to reference.
List<Map<String, Object?>> _templateRules(
  Map<String, Map<String, Object?>> ruleSets,
) {
  final geoipCn = _registerGeoRuleSet(ruleSets, 'geoip', 'cn');
  final geositeCn = _registerGeoRuleSet(ruleSets, 'geosite', 'cn');
  return [
    {'protocol': 'dns', 'action': 'hijack-dns'},
    {'ip_is_private': true, 'outbound': 'direct'},
    {
      'rule_set': [geoipCn],
      'outbound': 'direct',
    },
    {
      'rule_set': [geositeCn],
      'outbound': 'direct',
    },
  ];
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
  final degradations = <SingBoxDegradation>[];
  final outbounds = <Map<String, Object?>>[];
  final endpoints = <Map<String, Object?>>[];
  final nodeByName = <String, IrNode>{};
  final leafTags = <String>{'direct'};
  final leafOrder = <String>[];
  for (final node in profile.nodes) {
    nodeByName[node.name] = node;
    if (!singBoxContractNodeTypes.contains(node.type)) {
      degradations.add(_nodeProtocolDegradation(node));
      continue;
    }
    if (node.type == 'wireguard') {
      final endpoint = _wireGuardEndpoint(node, degradations);
      if (endpoint != null) {
        endpoints.add(endpoint);
        leafTags.add(node.name);
        leafOrder.add(node.name);
      }
      continue;
    }
    final outbound = _nodeToSingBox(node, degradations);
    if (outbound != null) {
      outbounds.add(outbound);
      leafTags.add(node.name);
      leafOrder.add(node.name);
    }
  }
  final sourceGroupNames = {
    for (final group in profile.groups) _asString(group['name']),
  };
  final groupByName = <String, Map<String, Object?>>{};
  final survivingGroups = <Map<String, Object?>>[];
  for (final group in profile.groups) {
    groupByName[_asString(group['name'])] = group;
    final outbound = _groupToSingBox(
      group,
      leafTags: leafTags,
      sourceGroupNames: sourceGroupNames,
      degradations: degradations,
    );
    if (outbound != null) survivingGroups.add(outbound);
  }
  outbounds.addAll(survivingGroups);
  outbounds.add(const {'type': 'direct', 'tag': 'direct'});
  final allTags = <String>{
    ...leafTags,
    for (final group in survivingGroups) group['tag'].toString(),
  };
  _applyDialerDetours(
    outbounds,
    endpoints,
    nodeByName,
    groupByName,
    allTags,
    degradations,
  );
  var primaryOutbound = 'direct';
  for (final group in survivingGroups) {
    if (group['type'] == 'selector') {
      primaryOutbound = group['tag'].toString();
      break;
    }
  }
  if (primaryOutbound == 'direct') {
    if (survivingGroups.isNotEmpty) {
      primaryOutbound = survivingGroups.first['tag'].toString();
    } else if (leafOrder.isNotEmpty) {
      primaryOutbound = leafOrder.first;
    }
  }
  final sourceRuleCount = profile.rules
      .where((line) => line.trim().isNotEmpty)
      .length;
  if (sourceRuleCount > 0) {
    degradations.add(
      SingBoxDegradation(
        kind: SingBoxDegradationKind.routing,
        name: '订阅分流规则',
        reason: '共 $sourceRuleCount 条订阅规则未移植，由内置模板替代',
        message:
            'subscription routing replaced by the built-in template '
            '($sourceRuleCount rule lines)',
      ),
    );
  }
  final ruleSets = <String, Map<String, Object?>>{};
  final rules = _templateRules(ruleSets);
  final dnsRuleSet = _asString(ruleSets['geosite-cn']?['tag'], 'geosite-cn');
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
          'detour': primaryOutbound,
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
      'rule_set': ruleSets.values.toList(),
      'final': primaryOutbound,
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
  return SingBoxRenderResult(config: config, degradations: degradations);
}

/// Maps Clash `dialer-proxy` onto detour, which outbounds and wireguard
/// endpoints both resolve at start in sing-box 1.14 (verified against
/// the 1.14.4 binary); unresolvable targets are named in the ledger
/// instead, and group outbounds have no detour field.
void _applyDialerDetours(
  List<Map<String, Object?>> outbounds,
  List<Map<String, Object?>> endpoints,
  Map<String, IrNode> nodeByName,
  Map<String, Map<String, Object?>> groupByName,
  Set<String> allTags,
  List<SingBoxDegradation> degradations,
) {
  void apply(Map<String, Object?> carrier, Object? dialer, String tag) {
    if (dialer is! String || dialer.isEmpty) return;
    final target = _target(dialer);
    if (target != tag && allTags.contains(target)) {
      carrier['detour'] = target;
    } else {
      degradations.add(
        SingBoxDegradation(
          kind: SingBoxDegradationKind.chain,
          name: tag,
          reason: '链式前置目标在 sing-box 下不可用，未写 detour',
          message:
              'dialer-proxy "$dialer" of "$tag" has no sing-box '
              'outbound',
        ),
      );
    }
  }

  for (final outbound in outbounds) {
    final tag = outbound['tag'].toString();
    final node = nodeByName[tag];
    if (node != null) {
      apply(outbound, node.params['dialer-proxy'], tag);
    } else if (groupByName.containsKey(tag)) {
      final dialer = groupByName[tag]?['dialer-proxy'];
      if (dialer is String && dialer.isNotEmpty) {
        degradations.add(
          SingBoxDegradation(
            kind: SingBoxDegradationKind.chain,
            name: tag,
            reason: '组级 dialer-proxy 在 sing-box 无对应字段',
            message:
                'dialer-proxy on proxy-group "$tag" is not supported '
                'in sing-box',
          ),
        );
      }
    }
  }
  for (final endpoint in endpoints) {
    final tag = endpoint['tag'].toString();
    final node = nodeByName[tag];
    if (node != null) {
      apply(endpoint, node.params['dialer-proxy'], tag);
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
    final endpoint = _asMap(entry);
    outboundTags.add(_asString(endpoint['tag']));
    outbounds.add(endpoint);
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
  // Resolvable is not enough: sing-box refuses a reference cycle at
  // start too, so the member/detour graph must stay acyclic.
  final edges = <String, List<String>>{};
  for (final outbound in outbounds) {
    final tag = _asString(outbound['tag']);
    edges[tag] = [
      for (final member in _asList(outbound['outbounds'])) member.toString(),
      if (outbound['detour'] != null) outbound['detour'].toString(),
    ];
  }
  final marks = <String, int>{};
  final stack = <String>[];
  void visit(String tag) {
    marks[tag] = 1;
    stack.add(tag);
    for (final next in edges[tag] ?? const <String>[]) {
      if (marks[next] == 1) {
        final cycle = [...stack.sublist(stack.indexOf(next)), next];
        problems.add('circular reference "${cycle.join('" -> "')}"');
      } else if (marks[next] == null && edges.containsKey(next)) {
        visit(next);
      }
    }
    stack.removeLast();
    marks[tag] = 2;
  }

  for (final tag in edges.keys) {
    if (marks[tag] == null) visit(tag);
  }
  return problems;
}
