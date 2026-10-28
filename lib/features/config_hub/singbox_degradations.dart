import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/singbox_native.dart';
import 'package:kfusion/features/config_hub/singbox_render.dart';

/// The core switch preflight's own render, run on the stored file: the
/// ledger ignores secret, ports and TUN, so the scan passes placeholders.
/// An unreadable file scans empty; validity stays the core's verdict.
List<SingBoxDegradation> singBoxDegradationsOf(String yamlText) {
  try {
    final clash = _asMap(loadPlainYaml(yamlText));
    if (clash.isEmpty) return const [];
    return renderSingBoxFromClash(clash, secret: '').degradations;
  } catch (_) {
    return const [];
  }
}

Future<List<SingBoxDegradation>> singBoxDegradationsTask(String yamlText) {
  return compute(singBoxDegradationsOf, yamlText);
}

/// One sidecar file beside the profile's YAML, in the switch's own
/// {kind, name, reason} shape; an empty ledger is no file at all.
class SingBoxDegradationStore {
  const SingBoxDegradationStore({Future<String> Function()? profilesDir})
    : _profilesDir = profilesDir;

  final Future<String> Function()? _profilesDir;

  Future<String> _filePath(int profileId) async {
    final dir = await (_profilesDir?.call() ?? appPath.profilesPath);
    return '$dir${Platform.pathSeparator}$profileId.degradations.json';
  }

  /// The stored ledger; null for a native sing-box profile, where no ledger applies.
  Future<List<SingBoxDegradation>?> read(int profileId) async {
    try {
      final text = await File(await _filePath(profileId)).readAsString();
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['format'] == 'singbox') return null;
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map && _kindOf(entry['kind']) != null)
            SingBoxDegradation(
              kind: _kindOf(entry['kind'])!,
              name: entry['name']?.toString() ?? '',
              reason: entry['reason']?.toString() ?? '',
              message: entry['reason']?.toString() ?? '',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(int profileId, List<SingBoxDegradation> items) async {
    if (items.isEmpty) {
      await remove(profileId);
      return;
    }
    final file = File(await _filePath(profileId));
    await file.writeAsString(
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }

  Future<void> writeNative(int profileId) async {
    final file = File(await _filePath(profileId));
    await file.writeAsString(jsonEncode({'format': 'singbox'}));
  }

  Future<void> remove(int profileId) async {
    try {
      final file = File(await _filePath(profileId));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

SingBoxDegradationKind? _kindOf(Object? name) {
  for (final kind in SingBoxDegradationKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}

final singBoxDegradationStoreProvider = Provider<SingBoxDegradationStore>(
  (ref) => const SingBoxDegradationStore(),
);

final profileDegradationsProvider =
    FutureProvider.family<List<SingBoxDegradation>?, int>(
      (ref, profileId) =>
          ref.watch(singBoxDegradationStoreProvider).read(profileId),
    );

// Never throws: a failed scan must not break its triggering profile flow.
Future<List<SingBoxDegradation>?> scanAndStoreSingBoxDegradations(
  SingBoxDegradationStore store,
  int profileId,
) async {
  try {
    final path = await appPath.getProfilePath(profileId.toString());
    final text = await readTextFileTask(path);
    if (text == null || text.isEmpty) {
      await store.write(profileId, const []);
      return const [];
    }
    if (isNativeSingBoxConfig(text)) {
      await store.writeNative(profileId);
      return null;
    }
    final items = await singBoxDegradationsTask(text);
    await store.write(profileId, items);
    return items;
  } catch (error) {
    commonPrint.log(
      'sing-box degradation scan failed for profile $profileId: $error',
      logLevel: LogLevel.warning,
    );
    return const [];
  }
}

/// The scan plus a watcher refresh, for notifier-side [Ref] holders.
Future<List<SingBoxDegradation>?> refreshSingBoxDegradations(
  Ref ref,
  int profileId,
) async {
  final items = await scanAndStoreSingBoxDegradations(
    ref.read(singBoxDegradationStoreProvider),
    profileId,
  );
  _invalidateDegradations(ref, profileId);
  return items;
}

Future<void> removeSingBoxDegradations(Ref ref, int profileId) async {
  await ref.read(singBoxDegradationStoreProvider).remove(profileId);
  _invalidateDegradations(ref, profileId);
}

/// The sidecar file is already written when this runs, so invalidation
/// is only a refresh hint for watchers in the same container. A ref
/// whose element died or was rebuilt during the scan has no live
/// watchers left to hint — a later container reads the file fresh —
/// and using it throws, so the hint is skipped instead. The check and
/// the invalidate stay in one synchronous run, so nothing can dispose
/// the element in between.
void _invalidateDegradations(Ref ref, int profileId) {
  if (ref.mounted) {
    ref.invalidate(profileDegradationsProvider(profileId));
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return {
      for (final MapEntry(:key, :value) in value.entries) key.toString(): value,
    };
  }
  return const {};
}
