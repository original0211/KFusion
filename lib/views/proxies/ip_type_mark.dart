import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/ip_quality/ip_quality_sheet.dart';
import 'package:kfusion/features/ip_quality/labels.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/node_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The exit-IP type mark in a proxy row's description line.
///
/// Watches the node's real exit leaf (a group's current leaf, never the
/// group itself) for as long as the row lives. An unknown type renders
/// nothing: the mark only ever shows a probed conclusion.
class NodeIpTypeSlot extends ConsumerStatefulWidget {
  const NodeIpTypeSlot({super.key, required this.proxy});

  final Proxy proxy;

  @override
  ConsumerState<NodeIpTypeSlot> createState() => _NodeIpTypeSlotState();
}

class _NodeIpTypeSlotState extends ConsumerState<NodeIpTypeSlot> {
  String? _target;
  late final NodeIpSweeper _sweeper;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _sweeper = ref.read(nodeIpSweeperProvider.notifier);
    _requestSync();
  }

  @override
  void dispose() {
    final target = _target;
    if (target != null) {
      _sweeper.unwatch(target);
    }
    super.dispose();
  }

  // The sweeper's state may not change while the tree that watches it is
  // still building, so watch changes always land after the frame.
  void _requestSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _syncTarget();
      setState(() {});
    });
  }

  String? _resolveTarget() {
    final isGroup = GroupType.values.any(
      (type) => type.name == widget.proxy.type,
    );
    final name = isGroup
        ? ref.read(realSelectedProxyStateProvider(widget.proxy.name)).proxyName
        : widget.proxy.name;
    return name == 'REJECT' ? null : name;
  }

  void _syncTarget() {
    final enabled = ref.read(appSettingProvider).probeNodeIpType;
    final next = enabled ? _resolveTarget() : null;
    if (next == _target) return;
    final previous = _target;
    _target = next;
    if (previous != null) _sweeper.unwatch(previous);
    if (next != null) _sweeper.watch(next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      appSettingProvider.select((state) => state.probeNodeIpType),
    );
    final target = _target;
    final reading = target == null
        ? null
        : ref.watch(nodeIpSweeperProvider.select((state) => state[target]));
    if ((enabled ? _resolveTarget() : null) != target) {
      _requestSync();
    }
    if (!enabled || target == null) return const SizedBox.shrink();
    final type = reading?.type;
    if (type != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: _IpTypeChip(
          type: type,
          ip: reading?.ip,
          onRefresh: () => _sweeper.refreshNode(target),
        ),
      );
    }
    if (reading?.phase == ProbePhase.probing) {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(
          context.appLocalizations.ipTypeProbing,
          maxLines: 1,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant.opacity50),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _IpTypeChip extends StatelessWidget {
  const _IpTypeChip({required this.type, required this.ip, this.onRefresh});

  final IpType type;
  final String? ip;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    // Rows fold business into the hosting label; the sheet keeps all four.
    final label = (type == IpType.business ? IpType.hosting : type).label(
      context,
    );
    final chip = DecoratedBox(
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.sm.copyWith(side: colorScheme.cabinRimSide),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Text(
          label,
          maxLines: 1,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
    final ip = this.ip;
    if (ip == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showIpQualitySheet(context, ip: ip),
      onLongPress: onRefresh,
      child: chip,
    );
  }
}
