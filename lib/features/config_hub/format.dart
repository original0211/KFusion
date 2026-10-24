import 'dart:convert';

/// The input formats the universal import understands.
enum ConfigFormat { clash, singbox, shareLinks, subscription }

/// Sniffs the format of an import payload without parsing it fully.
ConfigFormat detectFormat(String content) {
  final text = content.trim();
  if (text.startsWith('{') && text.contains('"outbounds"')) {
    return ConfigFormat.singbox;
  }
  if (text.contains('proxies:') ||
      text.contains('proxy-groups:') ||
      text.contains('rules:')) {
    return ConfigFormat.clash;
  }
  final decoded = tryDecodeBase64Text(text);
  if (decoded != null) {
    return ConfigFormat.subscription;
  }
  return ConfigFormat.shareLinks;
}

/// Decodes a base64 (standard or URL-safe, padding optional) payload to
/// readable text, or null when it does not decode to printable text.
String? tryDecodeBase64Text(String text) {
  final cleaned = text.trim().replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty || !RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(cleaned)) {
    return null;
  }
  var normalized = cleaned.replaceAll('-', '+').replaceAll('_', '/');
  while (normalized.length % 4 != 0) {
    normalized += '=';
  }
  try {
    final bytes = base64.decode(normalized);
    final decoded = utf8.decode(bytes, allowMalformed: false);
    if (decoded.runes.any(
      (rune) => rune < 0x09 || (rune > 0x0d && rune < 0x20),
    )) {
      return null;
    }
    return decoded;
  } catch (_) {
    return null;
  }
}
