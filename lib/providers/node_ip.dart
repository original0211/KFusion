import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kfusion/common/preferences.dart';
import 'package:kfusion/common/service_probe.dart';
import 'package:kfusion/core/singbox/singbox.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/core_kind.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/features/config_hub/singbox_render.dart';
import 'package:kfusion/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'config.dart';
import 'ip_quality.dart';
import 'outbound_ip.dart';
import 'routed_probe.dart';
import 'state.dart';

part 'generated/node_ip.g.dart';

/// What the proxies page knows about one node's exit: the probing phase,
/// the exit IP once read, and its probed type once classified.
@immutable
class NodeIpReading {
  const NodeIpReading({this.phase = ProbePhase.empty, this.ip, this.type});

  final ProbePhase phase;
  final String? ip;
  final IpType? type;

  @override
  bool operator ==(Object other) {
    return other is NodeIpReading &&
        other.phase == phase &&
        other.ip == ip &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(phase, ip, type);
}

typedef _CachedIp = ({String ip, DateTime at});

/// Fills in exit IPs and IP types for proxy rows on both cores.
///
/// The mihomo side rides the routed outbound-IP probe and mirrors its
/// entries; the sing-box side walks a serial queue over the injected probe
/// channel, so a probe never repoints a group the user is routed through.
/// Classification is shared: one lookup per exit IP, however many nodes
/// share it. Node-to-IP answers persist for a day per profile and are
/// dropped when the profile content moves on.
@Riverpod(keepAlive: true)
class NodeIpSweeper extends _$NodeIpSweeper {
  static const _mapTtl = Duration(hours: 24);

  final _watched = <String, int>{};
  final _sweepHeld = <String>{};
  final _probeWatched = <String>{};
  final _classifying = <String>{};
  final _sbQueue = <String>[];
  var _sbRunning = false;
  var _generation = 0;
  var _alive = true;
  Map<String, _CachedIp> _disk = const {};
  Future<void> _writeChain = Future.value();

  @override
  Map<String, NodeIpReading> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    ref.listen(appSettingProvider.select((state) => state.probeNodeIpType), (
      _,
      enabled,
    ) {
      if (!enabled) _reset(dropWatches: true);
    });
    ref.listen(activeCoreKindProvider, (_, _) => _reset(dropWatches: false));
    ref.listen(
      currentProfileProvider.select((profile) => profile?.id),
      (_, _) => _reset(dropWatches: false),
    );
    ref.listen(outboundIpProbeProvider, (_, next) => _mirror(next));
    ref.listen(delayDataSourceProvider, (_, next) => _onDelays(next));
    unawaited(_loadDisk());
    return const {};
  }

  NodeIpReading readingOf(String name) => state[name] ?? const NodeIpReading();

  bool get _enabled => ref.read(appSettingProvider).probeNodeIpType;

  bool get _isMihomo =>
      (ref.read(activeCoreKindProvider).value ?? CoreKind.mihomo) ==
      CoreKind.mihomo;

  void watch(String name) {
    if (!_alive || name.isEmpty) return;
    final count = (_watched[name] ?? 0) + 1;
    _watched[name] = count;
    if (count == 1) _ensure(name, front: true);
  }

  void unwatch(String name) {
    if (!_alive) return;
    final count = _watched[name] ?? 0;
    if (count > 1) {
      _watched[name] = count - 1;
      return;
    }
    _watched.remove(name);
    if (!_sweepHeld.contains(name)) _release(name);
  }

  /// Low-priority fill for a page's nodes, in display order. Work a row is
  /// waiting on goes first; a sweep lets go once its answer settles.
  void sweep(Iterable<String> names) {
    if (!_enabled) return;
    for (final name in names) {
      if (name.isEmpty) continue;
      final phase = state[name]?.phase;
      if (phase != null && phase != ProbePhase.empty) continue;
      if (_sweepHeld.add(name)) {
        _ensure(name);
        _settle(name);
      }
    }
  }

  /// Stops page-driven background work; rows keep their own watches.
  void cancelSweep() {
    for (final name in _sweepHeld.toList()) {
      _sweepHeld.remove(name);
      if (!_watched.containsKey(name)) _release(name);
    }
  }

  /// Manual re-probe of one node, ignoring its persisted answer.
  void refreshNode(String name) {
    if (!_enabled || name.isEmpty) return;
    _disk = {..._disk}..remove(name);
    _writeDisk();
    _set(name, const NodeIpReading());
    if (_isMihomo && _probeWatched.contains(name)) {
      ref.read(outboundIpProbeProvider.notifier).refresh([name]);
      _set(name, const NodeIpReading(phase: ProbePhase.probing));
    } else {
      _ensure(name, front: true);
    }
  }

  /// Manual re-probe of every node this page knows about.
  void refreshAll() {
    if (!_enabled) return;
    _disk = const {};
    _writeDisk();
    final names = {..._watched.keys, ..._sweepHeld};
    for (final name in names) {
      _set(name, const NodeIpReading());
    }
    if (_isMihomo) {
      ref
          .read(outboundIpProbeProvider.notifier)
          .refresh(_probeWatched.toList());
    }
    for (final name in names) {
      _ensure(name, front: true);
    }
  }

  void _ensure(String name, {bool front = false}) {
    if (!_enabled) return;
    final reading = state[name];
    final phase = reading?.phase;
    if (phase == ProbePhase.fresh || phase == ProbePhase.probing) return;
    final cached = _freshCache(name);
    if (cached != null) {
      _set(name, NodeIpReading(phase: ProbePhase.fresh, ip: cached));
      unawaited(_classifyIp(cached));
      return;
    }
    if (_isMihomo) {
      if (_probeWatched.add(name)) {
        ref.read(outboundIpProbeProvider.notifier).watch(name);
      }
      _set(
        name,
        NodeIpReading(
          phase: ProbePhase.probing,
          ip: reading?.ip,
          type: reading?.type,
        ),
      );
    } else {
      _enqueueSingBox(name, front: front);
    }
  }

  void _release(String name) {
    final held = _probeWatched.remove(name);
    _sbQueue.remove(name);
    if (held && _alive) {
      ref.read(outboundIpProbeProvider.notifier).unwatch(name);
    }
  }

  void _reset({required bool dropWatches}) {
    _generation++;
    for (final name in _probeWatched.toList()) {
      ref.read(outboundIpProbeProvider.notifier).unwatch(name);
    }
    _probeWatched.clear();
    _sbQueue.clear();
    _sweepHeld.clear();
    if (dropWatches) _watched.clear();
    if (state.isNotEmpty) state = const {};
    _disk = const {};
    unawaited(_loadDisk());
    if (!dropWatches) {
      for (final name in _watched.keys.toList()) {
        _ensure(name, front: true);
      }
    }
  }

  void _mirror(RoutedProbeState<String, IpInfo> probeState) {
    if (!_isMihomo) return;
    for (final name in _probeWatched.toList()) {
      final entry = probeState.entryOf(name);
      final reading = state[name];
      switch (entry.phase) {
        case ProbePhase.fresh:
          final ip = entry.value?.ip;
          if (ip == null) break;
          if (reading?.ip != ip || reading?.phase != ProbePhase.fresh) {
            _set(
              name,
              NodeIpReading(
                phase: ProbePhase.fresh,
                ip: ip,
                type: reading?.ip == ip ? reading?.type : null,
              ),
            );
            _persist(name, ip);
            unawaited(_classifyIp(ip));
          }
          _settle(name);
        case ProbePhase.probing:
          if (reading != null && reading.phase == ProbePhase.empty) {
            _set(
              name,
              NodeIpReading(
                phase: ProbePhase.probing,
                ip: reading.ip,
                type: reading.type,
              ),
            );
          }
        case ProbePhase.failed:
          if (reading == null || reading.ip == null) {
            _set(name, const NodeIpReading(phase: ProbePhase.failed));
          }
          _settle(name);
        case ProbePhase.empty:
          break;
      }
    }
  }

  void _onDelays(DelayMap delays) {
    if (!_enabled) return;
    sweep([
      for (final byName in delays.values)
        for (final MapEntry(:key, :value) in byName.entries)
          if (value != null) key,
    ]);
  }

  void _enqueueSingBox(String name, {bool front = false}) {
    final reading = state[name];
    _set(
      name,
      NodeIpReading(
        phase: ProbePhase.probing,
        ip: reading?.ip,
        type: reading?.type,
      ),
    );
    _sbQueue.remove(name);
    if (front) {
      _sbQueue.insert(0, name);
    } else {
      _sbQueue.add(name);
    }
    unawaited(_drainSingBox());
  }

  Future<void> _drainSingBox() async {
    if (_sbRunning) return;
    _sbRunning = true;
    final generation = _generation;
    try {
      while (_sbQueue.isNotEmpty) {
        if (generation != _generation || !_alive || !_enabled || _isMihomo)
          return;
        final name = _sbQueue.removeAt(0);
        if (!_watched.containsKey(name) && !_sweepHeld.contains(name)) {
          continue;
        }
        await _probeSingBox(name, generation);
      }
    } finally {
      _sbRunning = false;
    }
  }

  Future<void> _probeSingBox(String name, int generation) async {
    OutboundIpResult? result;
    try {
      var status = ref.read(singBoxActionProvider).value;
      status ??= await ref
          .read(singBoxActionProvider.future)
          .timeout(const Duration(seconds: 5));
      final api = ref.read(singBoxActionProvider.notifier).api;
      if (api != null && status.state == SingBoxState.running) {
        result = await lookupSingBoxOutboundIp(
          api,
          name,
          probeGroup: singBoxProbeSelectorTag,
          probePort: singBoxProbePort,
        );
      }
    } catch (_) {
      result = null;
    }
    if (generation != _generation || !_alive) return;
    final ip = result == null ? null : parseOutboundIp(result)?.ip;
    if (ip != null) {
      _set(name, NodeIpReading(phase: ProbePhase.fresh, ip: ip));
      _persist(name, ip);
      unawaited(_classifyIp(ip));
    } else {
      final reading = state[name];
      _set(
        name,
        NodeIpReading(
          phase: ProbePhase.failed,
          ip: reading?.ip,
          type: reading?.type,
        ),
      );
    }
    _settle(name);
  }

  Future<void> _classifyIp(String ip) async {
    if (!_classifying.add(ip)) return;
    final generation = _generation;
    try {
      final quality = await ref.read(ipQualityProvider(ip).future);
      if (generation != _generation || !_alive) return;
      var changed = false;
      final next = {...state};
      for (final MapEntry(:key, :value) in next.entries) {
        if (value.ip == ip && value.type != quality.type) {
          next[key] = NodeIpReading(
            phase: value.phase,
            ip: value.ip,
            type: quality.type,
          );
          changed = true;
        }
      }
      if (changed) state = Map.unmodifiable(next);
    } catch (_) {
      // A failed classification leaves the type unknown, never guessed.
    } finally {
      _classifying.remove(ip);
    }
  }

  void _settle(String name) {
    final phase = state[name]?.phase;
    if (phase != ProbePhase.fresh && phase != ProbePhase.failed) return;
    if (_sweepHeld.remove(name) && !_watched.containsKey(name)) {
      _release(name);
    }
  }

  void _set(String name, NodeIpReading reading) {
    if (state[name] == reading) return;
    state = Map.unmodifiable({...state, name: reading});
  }

  String? _freshCache(String name) {
    final entry = _disk[name];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > _mapTtl) return null;
    return entry.ip;
  }

  Future<void> _loadDisk() async {
    final generation = _generation;
    try {
      final profile = ref.read(currentProfileProvider);
      if (profile == null) return;
      final doc = await Preferences().getNodeIpMap();
      if (generation != _generation || !_alive) return;
      _applyDisk(doc, profile);
    } catch (_) {
      // A broken store only costs the cache, never the probing itself.
      return;
    }
  }

  void _applyDisk(Map<String, Object?> doc, Profile profile) {
    var loaded = const <String, _CachedIp>{};
    final section = doc['${profile.id}'];
    if (section is Map &&
        section['stamp'] == profile.lastUpdateDate?.millisecondsSinceEpoch) {
      final nodes = section['nodes'];
      if (nodes is Map) {
        loaded = {
          for (final MapEntry(:key, :value) in nodes.entries)
            if (value is Map && value['ip'] is String && value['ts'] is int)
              key.toString(): (
                ip: value['ip'] as String,
                at: DateTime.fromMillisecondsSinceEpoch(value['ts'] as int),
              ),
        };
      }
    }
    _disk = loaded;
    for (final name in {..._watched.keys, ..._sweepHeld}) {
      _ensure(name);
    }
  }

  void _persist(String name, String ip) {
    _disk = {..._disk, name: (ip: ip, at: DateTime.now())};
    _writeDisk();
  }

  void _writeDisk() {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    final snapshot = _disk;
    final stamp = profile.lastUpdateDate?.millisecondsSinceEpoch;
    _writeChain = _writeChain.then((_) async {
      try {
        final doc = await Preferences().getNodeIpMap();
        doc['${profile.id}'] = {
          'stamp': stamp,
          'nodes': {
            for (final MapEntry(:key, :value) in snapshot.entries)
              key: {'ip': value.ip, 'ts': value.at.millisecondsSinceEpoch},
          },
        };
        await Preferences().setNodeIpMap(doc);
      } catch (_) {
        // Persistence is best-effort; a failed write loses one answer.
      }
    });
  }
}
