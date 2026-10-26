import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kfusion/common/constant.dart';
import 'package:kfusion/common/service_probe.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/models/models.dart';

typedef SingBoxEchoFetch = Future<String?> Function(Uri url);

const _groupTypes = {'Selector', 'URLTest', 'Fallback', 'LoadBalance'};

// Null when the `now` chain is broken, cyclic or ends at a reject.
String? resolveSingBoxLeaf(Map<String, Object?> proxies, String name) {
  var current = name;
  if (current == 'DIRECT' && !proxies.containsKey(current)) {
    current = 'direct';
  }
  final seen = <String>{};
  while (seen.add(current)) {
    final entry = proxies[current];
    if (entry is! Map) return null;
    final type = entry['type']?.toString() ?? '';
    if (type == 'Reject') return null;
    if (!_groupTypes.contains(type)) return current;
    final now = entry['now']?.toString() ?? '';
    if (now.isEmpty) return null;
    current = now;
  }
  return null;
}

// Only the injected probe selector moves; the user's own groups never do.
Future<OutboundIpResult?> lookupSingBoxOutboundIp(
  SingBoxClashApi api,
  String proxyName, {
  required String probeGroup,
  required int probePort,
  Duration timeout = outboundIpTimeoutDuration,
  SingBoxEchoFetch? echoFetch,
}) async {
  final proxies = await api.getProxies();
  final all = proxies['proxies'];
  if (all is! Map) return null;
  final byName = <String, Object?>{
    for (final MapEntry(:key, :value) in all.entries) key.toString(): value,
  };
  final leaf = resolveSingBoxLeaf(byName, proxyName);
  if (leaf == null) return null;
  await api.selectProxy(probeGroup, leaf);
  final fetch = echoFetch ?? (url) => _fetchViaProbe(url, probePort, timeout);
  final completer = Completer<OutboundIpResult?>();
  var pending = ipInfoSources.length;
  for (final url in ipInfoSources.keys) {
    unawaited(() async {
      String? body;
      try {
        body = await fetch(Uri.parse(url));
      } catch (_) {
        body = null;
      }
      if (completer.isCompleted) return;
      final candidate = body == null
          ? null
          : OutboundIpResult(url: url, body: body, chains: [leaf]);
      if (candidate != null && parseOutboundIp(candidate) != null) {
        completer.complete(candidate);
      } else if (--pending == 0) {
        completer.complete(null);
      }
    }());
  }
  return completer.future.timeout(
    timeout + const Duration(seconds: 2),
    onTimeout: () => null,
  );
}

Future<String?> _fetchViaProbe(Uri url, int probePort, Duration timeout) async {
  final client = HttpClient();
  // The app-wide HttpOverrides would route this through the live proxy;
  // the probe inbound is the one route this fetch may take.
  client.findProxy = (_) => 'PROXY 127.0.0.1:$probePort';
  client.connectionTimeout = timeout;
  try {
    final request = await client.getUrl(url).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return null;
    return await response.transform(utf8.decoder).join().timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
