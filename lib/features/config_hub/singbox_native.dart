import 'dart:convert';

import 'package:kfusion/features/config_hub/format.dart';

/// Whether [text] is a native sing-box JSON config, by the import layer's own sniff.
bool isNativeSingBoxConfig(String text) {
  return detectFormat(text) == ConfigFormat.singbox;
}

Map<String, Object?>? decodeSingBoxConfig(String text) {
  final doc = _decodeJsonObject(text);
  if (doc == null) return null;
  return {
    for (final MapEntry(:key, :value) in doc.entries) key.toString(): value,
  };
}

Map<dynamic, dynamic>? _decodeJsonObject(String text) {
  try {
    final decoded = json.decode(text);
    return decoded is Map ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Why a native config cannot be handed to the kernel as-is; null
/// when its structure is sound — the kernel's check is the deep verdict.
String? nativeSingBoxConfigProblem(String text) {
  final Object? decoded;
  try {
    decoded = json.decode(text);
  } catch (_) {
    return '配置不是合法的 JSON，无法按 sing-box 原生配置使用';
  }
  if (decoded is! Map) {
    return '配置顶层不是 JSON 对象，无法按 sing-box 原生配置使用';
  }
  final outbounds = decoded['outbounds'];
  if (outbounds is! List || outbounds.isEmpty) {
    return '配置缺少 outbounds，无法按 sing-box 原生配置使用';
  }
  final usableOutbound = outbounds.any(
    (outbound) =>
        outbound is Map &&
        outbound['type'] != 'direct' &&
        outbound['type'] != 'block' &&
        outbound['type'] != 'dns',
  );
  final endpoints = decoded['endpoints'];
  final usableEndpoint = endpoints is List && endpoints.isNotEmpty;
  if (!usableOutbound && !usableEndpoint) {
    return '没有可供 sing-box 使用的代理出站，配置中仅有 direct/block 出站';
  }
  return null;
}

/// The clash_api endpoint a native config declares; null when it offers none the app can take over.
({int port, String secret})? nativeSingBoxClashApi(Map<String, Object?> doc) {
  final experimental = doc['experimental'];
  if (experimental is! Map) return null;
  final clashApi = experimental['clash_api'];
  if (clashApi is! Map) return null;
  final controller = clashApi['external_controller']?.toString() ?? '';
  if (controller.isEmpty) return null;
  final colon = controller.lastIndexOf(':');
  final port = colon == -1
      ? 9090
      : int.tryParse(controller.substring(colon + 1));
  if (port == null) return null;
  return (port: port, secret: clashApi['secret']?.toString() ?? '');
}

int? nativeSingBoxMixedPort(Map<String, Object?> doc) {
  final inbounds = doc['inbounds'];
  if (inbounds is! List) return null;
  for (final inbound in inbounds) {
    if (inbound is Map && inbound['type'] == 'mixed') {
      final port = inbound['listen_port'];
      if (port is num) return port.toInt();
    }
  }
  return null;
}

bool nativeSingBoxUsesTun(Map<String, Object?> doc) {
  final inbounds = doc['inbounds'];
  if (inbounds is! List) return false;
  return inbounds.any((inbound) => inbound is Map && inbound['type'] == 'tun');
}
