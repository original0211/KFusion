import 'dart:async';
import 'dart:convert';

import 'package:kfusion/common/boot_record.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/common/system_dns.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Preferences {
  static Preferences? _instance;
  var _store = ResolveOnce(_open);

  Future<bool> get isInit async => await _store.value != null;

  Preferences._internal();

  static Future<SharedPreferences?> _open() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  Future<void> rebind() async {
    _store = ResolveOnce(_open);
    await _store.value;
  }

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  /// Beginner mode for the KFusion UI. New installs default to true so
  /// the simplified import flow is what a first-time user meets.
  Future<bool> getBeginnerMode() async {
    final preferences = await _store.value;
    return preferences?.getBool('beginnerMode') ?? true;
  }

  Future<void> setBeginnerMode(bool value) async {
    final preferences = await _store.value;
    await preferences?.setBool('beginnerMode', value);
  }

  Future<Map<int, String>> getCoreKindMap() async {
    final preferences = await _store.value;
    final raw = preferences?.getString('coreKinds');
    if (raw == null) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (int.tryParse(key.toString()) != null)
            int.parse(key.toString()): value.toString(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> setCoreKindMap(Map<int, String> kinds) async {
    final preferences = await _store.value;
    await preferences?.setString(
      'coreKinds',
      json.encode({for (final e in kinds.entries) e.key.toString(): e.value}),
    );
  }

  Future<String> getActiveCoreKind() async {
    final preferences = await _store.value;
    return preferences?.getString('activeCoreKind') ?? 'mihomo';
  }

  Future<void> setActiveCoreKind(String value) async {
    final preferences = await _store.value;
    await preferences?.setString('activeCoreKind', value);
  }

  Future<bool> getSingBoxTunEnabled() async {
    final preferences = await _store.value;
    return preferences?.getBool('singboxTunEnabled') ?? false;
  }

  Future<void> setSingBoxTunEnabled(bool value) async {
    final preferences = await _store.value;
    await preferences?.setBool('singboxTunEnabled', value);
  }

  Future<String?> getSingBoxBinaryPath() async {
    final preferences = await _store.value;
    return preferences?.getString('singboxBinaryPath');
  }

  Future<void> setSingBoxBinaryPath(String? value) async {
    final preferences = await _store.value;
    if (value == null) {
      await preferences?.remove('singboxBinaryPath');
    } else {
      await preferences?.setString('singboxBinaryPath', value);
    }
  }

  Future<int> getVersion() async {
    final preferences = await _store.value;
    return preferences?.getInt('version') ?? 0;
  }

  Future<void> setVersion(int version) async {
    final preferences = await _store.value;
    await preferences?.setInt('version', version);
  }

  Future<int> getUpgradeVersion() async {
    final preferences = await _store.value;
    return preferences?.getInt('upgradeVersion') ?? 0;
  }

  Future<void> setUpgradeVersion(int version) async {
    final preferences = await _store.value;
    await preferences?.setInt('upgradeVersion', version);
  }

  Future<void> saveShareState(SharedState shareState) async {
    final preferences = await _store.value;
    await preferences?.setString('sharedState', json.encode(shareState));
  }

  Future<Map<String, Object?>?> getConfigMap() async {
    try {
      final preferences = await _store.value;
      final configString = preferences?.getString(configKey);
      if (configString == null) return null;
      final Map<String, Object?>? configMap = json.decode(configString);
      return configMap;
    } catch (e) {
      commonPrint.log(
        'getConfigMap error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<Map<String, Object?>?> getClashConfigMap() async {
    try {
      final preferences = await _store.value;
      final clashConfigString = preferences?.getString(clashConfigKey);
      if (clashConfigString == null) return null;
      return json.decode(clashConfigString);
    } catch (e) {
      commonPrint.log(
        'getClashConfigMap error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> clearClashConfig() async {
    try {
      final preferences = await _store.value;
      await preferences?.remove(clashConfigKey);
      return;
    } catch (e) {
      commonPrint.log(
        'clearClashConfig error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return;
    }
  }

  Future<Config?> getConfig() async {
    final configMap = await getConfigMap();
    if (configMap == null) {
      return null;
    }
    return Config.fromJson(configMap);
  }

  Future<bool> saveConfig(Config config) async {
    final preferences = await _store.value;
    return preferences?.setString(configKey, json.encode(config)) ?? false;
  }

  Future<SystemDnsRecord?> getSystemDnsRecord() async {
    try {
      final sharedPreferencesIns = await _store.value;
      final raw = sharedPreferencesIns?.getString(systemDnsRecordKey);
      if (raw == null) {
        return null;
      }
      return SystemDnsRecord.fromJson(json.decode(raw));
    } catch (e) {
      commonPrint.log(
        'getSystemDnsRecord error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> saveSystemDnsRecord(SystemDnsRecord record) async {
    final sharedPreferencesIns = await _store.value;
    await sharedPreferencesIns?.setString(
      systemDnsRecordKey,
      json.encode(record),
    );
  }

  Future<void> clearSystemDnsRecord() async {
    final sharedPreferencesIns = await _store.value;
    await sharedPreferencesIns?.remove(systemDnsRecordKey);
  }

  Future<BootRecord?> getBootRecord() async {
    try {
      final sharedPreferencesIns = await _store.value;
      final raw = sharedPreferencesIns?.getString(bootRecordKey);
      if (raw == null) {
        return null;
      }
      return BootRecord.fromJson(json.decode(raw));
    } catch (e) {
      commonPrint.log(
        'getBootRecord error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> saveBootRecord(BootRecord record) async {
    final sharedPreferencesIns = await _store.value;
    await sharedPreferencesIns?.setString(bootRecordKey, json.encode(record));
  }

  Future<void> clearPreferences() async {
    final sharedPreferencesIns = await _store.value;
    await sharedPreferencesIns?.clear();
  }
}

final preferences = Preferences();
