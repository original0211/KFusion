// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../node_ip.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Fills in exit IPs and IP types for proxy rows on both cores.
///
/// The mihomo side rides the routed outbound-IP probe and mirrors its
/// entries; the sing-box side walks a serial queue over the injected probe
/// channel, so a probe never repoints a group the user is routed through.
/// Classification is shared: one lookup per exit IP, however many nodes
/// share it. Node-to-IP answers persist for a day per profile and are
/// dropped when the profile content moves on.

@ProviderFor(NodeIpSweeper)
final nodeIpSweeperProvider = NodeIpSweeperProvider._();

/// Fills in exit IPs and IP types for proxy rows on both cores.
///
/// The mihomo side rides the routed outbound-IP probe and mirrors its
/// entries; the sing-box side walks a serial queue over the injected probe
/// channel, so a probe never repoints a group the user is routed through.
/// Classification is shared: one lookup per exit IP, however many nodes
/// share it. Node-to-IP answers persist for a day per profile and are
/// dropped when the profile content moves on.
final class NodeIpSweeperProvider
    extends $NotifierProvider<NodeIpSweeper, Map<String, NodeIpReading>> {
  /// Fills in exit IPs and IP types for proxy rows on both cores.
  ///
  /// The mihomo side rides the routed outbound-IP probe and mirrors its
  /// entries; the sing-box side walks a serial queue over the injected probe
  /// channel, so a probe never repoints a group the user is routed through.
  /// Classification is shared: one lookup per exit IP, however many nodes
  /// share it. Node-to-IP answers persist for a day per profile and are
  /// dropped when the profile content moves on.
  NodeIpSweeperProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nodeIpSweeperProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nodeIpSweeperHash();

  @$internal
  @override
  NodeIpSweeper create() => NodeIpSweeper();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, NodeIpReading> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, NodeIpReading>>(value),
    );
  }
}

String _$nodeIpSweeperHash() => r'a6a5a69dbb47792b6474abcef866843b63f26030';

/// Fills in exit IPs and IP types for proxy rows on both cores.
///
/// The mihomo side rides the routed outbound-IP probe and mirrors its
/// entries; the sing-box side walks a serial queue over the injected probe
/// channel, so a probe never repoints a group the user is routed through.
/// Classification is shared: one lookup per exit IP, however many nodes
/// share it. Node-to-IP answers persist for a day per profile and are
/// dropped when the profile content moves on.

abstract class _$NodeIpSweeper extends $Notifier<Map<String, NodeIpReading>> {
  Map<String, NodeIpReading> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<Map<String, NodeIpReading>, Map<String, NodeIpReading>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, NodeIpReading>,
                Map<String, NodeIpReading>
              >,
              Map<String, NodeIpReading>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
