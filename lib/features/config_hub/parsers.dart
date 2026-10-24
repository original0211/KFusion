import 'dart:convert';

import 'package:kfusion/common/yaml.dart';
import 'package:kfusion/features/config_hub/format.dart';
import 'package:kfusion/features/config_hub/ir.dart';

/// Parses any import payload by sniffing its format first.
IrParseResult parseConfig(String content) {
  switch (detectFormat(content)) {
    case ConfigFormat.clash:
      return fromClash(content);
    case ConfigFormat.singbox:
      return fromSingBox(content);
    case ConfigFormat.subscription:
      return fromSubscriptionText(content);
    case ConfigFormat.shareLinks:
      return fromShareLinks(content);
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return {
      for (final MapEntry(:key, :value) in value.entries)
        key.toString(): value,
    };
  }
  return const {};
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}

int _asPort(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

String _asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

/// Parses a Clash YAML config, keeping proxies, groups and rules verbatim.
IrParseResult fromClash(String content) {
  final doc = _asMap(loadPlainYaml(content));
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
  return IrParseResult(
    profile: IrProfile(
      nodes: nodes,
      groups: [
        for (final entry in _asList(doc['proxy-groups'])) _asMap(entry),
      ],
      rules: [
        for (final entry in _asList(doc['rules'])) entry.toString(),
      ],
    ),
  );
}

/// Parses a sing-box JSON config. Proxy outbounds become Clash nodes;
/// selector/urltest outbounds become Clash groups; direct/block/dns
/// outbounds are skipped, not nodes.
IrParseResult fromSingBox(String content) {
  final doc = _asMap(json.decode(content));
  final nodes = <IrNode>[];
  final groups = <Map<String, Object?>>[];
  final unsupported = <String>[];
  final skipped = <String>[];
  for (final entry in _asList(doc['outbounds'])) {
    final outbound = _asMap(entry);
    final type = _asString(outbound['type']);
    final tag = _asString(outbound['tag']);
    switch (type) {
      case 'direct':
      case 'block':
      case 'dns':
        if (tag.isNotEmpty) skipped.add(tag);
      case 'selector':
        groups.add({
          'name': tag,
          'type': 'select',
          'proxies': [
            for (final name in _asList(outbound['outbounds']))
              name.toString(),
          ],
        });
      case 'urltest':
        groups.add({
          'name': tag,
          'type': 'url-test',
          'proxies': [
            for (final name in _asList(outbound['outbounds']))
              name.toString(),
          ],
          if (outbound['url'] != null) 'url': outbound['url'],
          if (outbound['interval'] != null) 'interval': outbound['interval'],
          if (outbound['tolerance'] != null)
            'tolerance': outbound['tolerance'],
        });
      case 'shadowsocks':
      case 'vmess':
      case 'vless':
      case 'trojan':
      case 'hysteria2':
      case 'tuic':
      case 'wireguard':
      case 'socks':
      case 'http':
        final node = _singboxNode(outbound);
        if (node != null) nodes.add(node);
      default:
        unsupported.add('outbound type "$type"');
    }
  }
  return IrParseResult(
    profile: IrProfile(nodes: nodes, groups: groups),
    unsupported: unsupported,
    skipped: skipped,
  );
}

const _singboxTypeToClash = {
  'shadowsocks': 'ss',
  'vmess': 'vmess',
  'vless': 'vless',
  'trojan': 'trojan',
  'hysteria2': 'hysteria2',
  'tuic': 'tuic',
  'wireguard': 'wireguard',
  'socks': 'socks5',
  'http': 'http',
};

/// Keys consumed by the sing-box to Clash field mapping itself.
const _consumedSingboxKeys = {
  'tag',
  'type',
  'server',
  'server_port',
  'method',
  'security',
  'alter_id',
  'transport',
  'tls',
  'local_address',
  'private_key',
  'peer_public_key',
  'pre_shared_key',
  'peers',
  'version',
};

Map<String, Object?> _mapTls(Object? tlsValue) {
  final tls = _asMap(tlsValue);
  if (tls.isEmpty || tls['enabled'] == false) return const {};
  final mapped = <String, Object?>{'tls': true};
  if (tls['server_name'] != null) mapped['servername'] = tls['server_name'];
  if (tls['insecure'] == true) mapped['skip-cert-verify'] = true;
  if (tls['alpn'] != null) mapped['alpn'] = tls['alpn'];
  final reality = _asMap(tls['reality']);
  if (reality['enabled'] == true) {
    mapped['reality-opts'] = {
      if (reality['public_key'] != null) 'public-key': reality['public_key'],
      if (reality['short_id'] != null) 'short-id': reality['short_id'],
    };
  }
  return mapped;
}

Map<String, Object?> _mapTransport(Object? transportValue) {
  final transport = _asMap(transportValue);
  final type = _asString(transport['type']);
  if (type.isEmpty) return const {};
  final mapped = <String, Object?>{'network': type};
  switch (type) {
    case 'ws':
      mapped['ws-opts'] = {
        if (transport['path'] != null) 'path': transport['path'],
        if (transport['headers'] != null) 'headers': transport['headers'],
      };
    case 'grpc':
      mapped['grpc-opts'] = {
        if (transport['service_name'] != null)
          'grpc-service-name': transport['service_name'],
      };
    case 'http':
      mapped['http-opts'] = {
        if (transport['path'] != null) 'path': transport['path'],
        if (transport['headers'] != null) 'headers': transport['headers'],
      };
    case 'h2':
      mapped['h2-opts'] = {
        if (transport['host'] != null) 'host': transport['host'],
        if (transport['path'] != null) 'path': transport['path'],
      };
  }
  return mapped;
}

IrNode? _singboxNode(Map<String, Object?> outbound) {
  final type = _asString(outbound['type']);
  final clashType = _singboxTypeToClash[type];
  if (clashType == null) return null;
  final params = <String, Object?>{};
  params.addAll(_mapTransport(outbound['transport']));
  params.addAll(_mapTls(outbound['tls']));
  switch (type) {
    case 'shadowsocks':
      if (outbound['method'] != null) params['cipher'] = outbound['method'];
      if (outbound['password'] != null) {
        params['password'] = outbound['password'];
      }
    case 'vmess':
      if (outbound['uuid'] != null) params['uuid'] = outbound['uuid'];
      if (outbound['security'] != null) {
        params['cipher'] = outbound['security'];
      }
      if (outbound['alter_id'] != null) {
        params['alterId'] = outbound['alter_id'];
      }
    case 'vless':
      if (outbound['uuid'] != null) params['uuid'] = outbound['uuid'];
      if (outbound['flow'] != null) params['flow'] = outbound['flow'];
    case 'trojan':
      if (outbound['password'] != null) {
        params['password'] = outbound['password'];
      }
    case 'hysteria2':
      if (outbound['password'] != null) {
        params['password'] = outbound['password'];
      }
      final obfs = _asMap(outbound['obfs']);
      if (obfs['type'] != null) params['obfs'] = obfs['type'];
      if (obfs['password'] != null) params['obfs-password'] = obfs['password'];
      final tls = _asMap(outbound['tls']);
      if (tls['server_name'] != null) params['sni'] = tls['server_name'];
    case 'tuic':
      if (outbound['uuid'] != null) params['uuid'] = outbound['uuid'];
      if (outbound['password'] != null) {
        params['password'] = outbound['password'];
      }
      if (outbound['congestion_control'] != null) {
        params['congestion-controller'] = outbound['congestion_control'];
      }
      if (outbound['udp_relay_mode'] != null) {
        params['udp-relay-mode'] = outbound['udp_relay_mode'];
      }
    case 'wireguard':
      final local = _asList(outbound['local_address']);
      if (local.isNotEmpty) {
        final first = local.first.toString().split('/').first;
        if (first.contains(':')) {
          params['ipv6'] = first;
        } else {
          params['ip'] = first;
        }
      }
      if (outbound['private_key'] != null) {
        params['private-key'] = outbound['private_key'];
      }
      if (outbound['peer_public_key'] != null) {
        params['public-key'] = outbound['peer_public_key'];
      }
      if (outbound['pre_shared_key'] != null) {
        params['preshared-key'] = outbound['pre_shared_key'];
      }
      if (outbound['reserved'] != null) {
        params['reserved'] = outbound['reserved'];
      }
      final peers = _asList(outbound['peers']);
      if (peers.isNotEmpty) {
        final peer = _asMap(peers.first);
        if (peer['public_key'] != null) {
          params['public-key'] = peer['public_key'];
        }
        if (peer['pre_shared_key'] != null) {
          params['preshared-key'] = peer['pre_shared_key'];
        }
        if (peer['reserved'] != null) params['reserved'] = peer['reserved'];
      }
    case 'socks':
    case 'http':
      if (outbound['username'] != null) {
        params['username'] = outbound['username'];
      }
      if (outbound['password'] != null) {
        params['password'] = outbound['password'];
      }
  }
  for (final MapEntry(:key, :value) in outbound.entries) {
    if (!_consumedSingboxKeys.contains(key) && !params.containsKey(key)) {
      params[key] = value;
    }
  }
  return IrNode(
    name: _asString(outbound['tag']),
    type: clashType,
    server: _asString(outbound['server']),
    port: _asPort(outbound['server_port']),
    params: params,
  );
}

/// Parses one share link per line. Unknown schemes land in [unsupported]
/// instead of aborting the whole batch.
IrParseResult fromShareLinks(String content) {
  final nodes = <IrNode>[];
  final unsupported = <String>[];
  for (final rawLine in content.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (!line.contains('://')) {
      unsupported.add('unknown://');
      continue;
    }
    final scheme = line.split('://').first.toLowerCase();
    final node = switch (scheme) {
      'ss' => _parseSsLink(line),
      'vmess' => _parseVmessLink(line),
      'vless' || 'trojan' || 'hysteria2' || 'hy2' || 'tuic' =>
        _parseUrlLink(line),
      _ => null,
    };
    if (node == null) {
      unsupported.add('$scheme://');
    } else {
      nodes.add(node);
    }
  }
  return IrParseResult(
    profile: IrProfile(nodes: nodes),
    unsupported: unsupported,
  );
}

/// Parses a base64 subscription: the decoded payload is dispatched back to
/// the Clash, sing-box or share-link parser as its shape dictates.
IrParseResult fromSubscriptionText(String content) {
  final decoded = tryDecodeBase64Text(content.trim()) ?? content;
  final trimmed = decoded.trim();
  if (trimmed.startsWith('{')) {
    try {
      return fromSingBox(trimmed);
    } catch (_) {
      return fromShareLinks(trimmed);
    }
  }
  if (trimmed.contains('proxies:') ||
      trimmed.contains('proxy-groups:') ||
      trimmed.contains('rules:')) {
    return fromClash(trimmed);
  }
  return fromShareLinks(trimmed);
}

String _decodeLinkPart(String value) {
  final cleaned = value.trim().replaceAll('-', '+').replaceAll('_', '/');
  var padded = cleaned;
  while (padded.length % 4 != 0) {
    padded += '=';
  }
  try {
    return utf8.decode(base64.decode(padded));
  } catch (_) {
    return value;
  }
}

(String, String) _splitName(String rest) {
  final hash = rest.indexOf('#');
  if (hash == -1) return (rest, '');
  return (
    rest.substring(0, hash),
    Uri.decodeComponent(rest.substring(hash + 1)),
  );
}

(String, Map<String, String>) _splitQuery(String rest) {
  final mark = rest.indexOf('?');
  if (mark == -1) return (rest, const {});
  return (
    rest.substring(0, mark),
    Uri.splitQueryString(rest.substring(mark + 1)),
  );
}

IrNode? _parseSsLink(String line) {
  final body = line.substring('ss://'.length);
  final (withoutName, name) = _splitName(body);
  final (withoutQuery, query) = _splitQuery(withoutName);
  String userinfo;
  String hostport;
  if (withoutQuery.contains('@')) {
    final at = withoutQuery.lastIndexOf('@');
    userinfo = withoutQuery.substring(0, at);
    hostport = withoutQuery.substring(at + 1);
    if (!userinfo.contains(':')) {
      userinfo = _decodeLinkPart(userinfo);
    }
  } else {
    final decoded = _decodeLinkPart(withoutQuery);
    final at = decoded.lastIndexOf('@');
    if (at == -1) return null;
    userinfo = decoded.substring(0, at);
    hostport = decoded.substring(at + 1);
  }
  final colon = userinfo.indexOf(':');
  if (colon == -1) return null;
  final method = userinfo.substring(0, colon);
  final password = userinfo.substring(colon + 1);
  final portColon = hostport.lastIndexOf(':');
  if (portColon == -1) return null;
  final params = <String, Object?>{
    'cipher': method,
    'password': password,
  };
  final plugin = query['plugin'];
  if (plugin != null && plugin.isNotEmpty) {
    final parts = plugin.split(';');
    params['plugin'] = parts.first;
    final opts = <String, Object?>{};
    for (final part in parts.skip(1)) {
      final eq = part.indexOf('=');
      if (eq != -1) opts[part.substring(0, eq)] = part.substring(eq + 1);
    }
    if (opts.isNotEmpty) params['plugin-opts'] = opts;
  }
  return IrNode(
    name: name,
    type: 'ss',
    server: hostport.substring(0, portColon),
    port: _asPort(hostport.substring(portColon + 1)),
    params: params,
  );
}

IrNode? _parseVmessLink(String line) {
  final body = line.substring('vmess://'.length);
  final (withoutName, _) = _splitName(body);
  try {
    final json = _asMap(jsonDecode(_decodeLinkPart(withoutName)));
    final params = <String, Object?>{
      'uuid': json['id'],
      if (json['aid'] != null) 'alterId': _asPort(json['aid']),
      if (json['scy'] != null) 'cipher': json['scy'],
    };
    final net = _asString(json['net']);
    if (net.isNotEmpty) params['network'] = net;
    if (json['tls'] == 'tls') params['tls'] = true;
    if (json['sni'] != null) params['servername'] = json['sni'];
    if (json['alpn'] != null) {
      params['alpn'] = _asString(json['alpn']).split(',');
    }
    final host = _asString(json['host']);
    final path = _asString(json['path']);
    switch (net) {
      case 'ws':
        params['ws-opts'] = {
          if (path.isNotEmpty) 'path': path,
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
      case 'grpc':
        params['grpc-opts'] = {
          if (path.isNotEmpty) 'grpc-service-name': path,
        };
      case 'h2':
        params['h2-opts'] = {
          if (host.isNotEmpty) 'host': [host],
          if (path.isNotEmpty) 'path': path,
        };
      case 'http':
        params['http-opts'] = {
          if (path.isNotEmpty) 'path': path,
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
    }
    params.removeWhere((_, value) => value == null);
    return IrNode(
      name: _asString(json['ps']),
      type: 'vmess',
      server: _asString(json['add']),
      port: _asPort(json['port']),
      params: params,
    );
  } catch (_) {
    return null;
  }
}

List<String>? _splitAlpn(String? value) {
  if (value == null || value.isEmpty) return null;
  return value.split(',');
}

IrNode? _parseUrlLink(String line) {
  final scheme = line.split('://').first.toLowerCase();
  final body = line.substring(scheme.length + 3);
  final (withoutName, name) = _splitName(body);
  final uri = Uri.tryParse('$scheme://$withoutName');
  if (uri == null || uri.host.isEmpty) return null;
  final query = uri.queryParameters;
  final params = <String, Object?>{};
  switch (scheme) {
    case 'vless':
      params['uuid'] = uri.userInfo;
      if (query['flow'] != null) params['flow'] = query['flow'];
      final security = query['security'] ?? '';
      if (security == 'tls' || security == 'reality') params['tls'] = true;
      if (query['sni'] != null) params['servername'] = query['sni'];
      if (query['alpn'] != null) params['alpn'] = _splitAlpn(query['alpn']);
      if (query['fp'] != null) params['fingerprint'] = query['fp'];
      if (security == 'reality') {
        params['reality-opts'] = {
          if (query['pbk'] != null) 'public-key': query['pbk'],
          if (query['sid'] != null) 'short-id': query['sid'],
        };
      }
      final network = query['type'] ?? 'tcp';
      if (network != 'tcp') params['network'] = network;
      if (network == 'ws') {
        params['ws-opts'] = {
          if (query['path'] != null) 'path': query['path'],
          if (query['host'] != null) 'headers': {'Host': query['host']},
        };
      } else if (network == 'grpc') {
        params['grpc-opts'] = {
          if (query['serviceName'] != null)
            'grpc-service-name': query['serviceName'],
        };
      }
      return IrNode(
        name: name,
        type: 'vless',
        server: uri.host,
        port: uri.port,
        params: params,
      );
    case 'trojan':
      params['password'] = Uri.decodeComponent(uri.userInfo);
      if (query['sni'] != null) params['sni'] = query['sni'];
      if (query['alpn'] != null) params['alpn'] = _splitAlpn(query['alpn']);
      if (query['security'] == 'tls') params['tls'] = true;
      final trojanNetwork = query['type'];
      if (trojanNetwork != null && trojanNetwork != 'tcp') {
        params['network'] = trojanNetwork;
      }
      if (trojanNetwork == 'ws') {
        params['ws-opts'] = {
          if (query['path'] != null) 'path': query['path'],
          if (query['host'] != null) 'headers': {'Host': query['host']},
        };
      }
      return IrNode(
        name: name,
        type: 'trojan',
        server: uri.host,
        port: uri.port,
        params: params,
      );
    case 'hysteria2':
    case 'hy2':
      params['password'] = Uri.decodeComponent(uri.userInfo);
      if (query['obfs'] != null) params['obfs'] = query['obfs'];
      if (query['obfs-password'] != null) {
        params['obfs-password'] = query['obfs-password'];
      }
      if (query['sni'] != null) params['sni'] = query['sni'];
      if (query['alpn'] != null) params['alpn'] = _splitAlpn(query['alpn']);
      if (query['insecure'] == '1') params['skip-cert-verify'] = true;
      return IrNode(
        name: name,
        type: 'hysteria2',
        server: uri.host,
        port: uri.port,
        params: params,
      );
    case 'tuic':
      final userInfo = Uri.decodeComponent(uri.userInfo);
      final colon = userInfo.indexOf(':');
      if (colon == -1) return null;
      params['uuid'] = userInfo.substring(0, colon);
      params['password'] = userInfo.substring(colon + 1);
      if (query['congestion_control'] != null) {
        params['congestion-controller'] = query['congestion_control'];
      }
      if (query['udp_relay_mode'] != null) {
        params['udp-relay-mode'] = query['udp_relay_mode'];
      }
      if (query['sni'] != null) params['sni'] = query['sni'];
      if (query['alpn'] != null) params['alpn'] = _splitAlpn(query['alpn']);
      return IrNode(
        name: name,
        type: 'tuic',
        server: uri.host,
        port: uri.port,
        params: params,
      );
  }
  return null;
}
