import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

// Kinds outside this order (today only nodeUnusable) collect under Other.
const singBoxDegradationGroupOrder = [
  SingBoxDegradationKind.nodeProtocol,
  SingBoxDegradationKind.groupType,
  SingBoxDegradationKind.groupNested,
  SingBoxDegradationKind.groupMember,
  SingBoxDegradationKind.groupDropped,
  SingBoxDegradationKind.chain,
  SingBoxDegradationKind.routing,
];

// A null kind marks the Other bucket.
List<(SingBoxDegradationKind?, List<SingBoxDegradation>)>
groupSingBoxDegradations(List<SingBoxDegradation> items) {
  final groups = <(SingBoxDegradationKind?, List<SingBoxDegradation>)>[];
  for (final kind in singBoxDegradationGroupOrder) {
    final bucket = [
      for (final item in items)
        if (item.kind == kind) item,
    ];
    if (bucket.isNotEmpty) groups.add((kind, bucket));
  }
  final rest = [
    for (final item in items)
      if (!singBoxDegradationGroupOrder.contains(item.kind)) item,
  ];
  if (rest.isNotEmpty) groups.add((null, rest));
  return groups;
}

String singBoxDegradationKindTitle(
  AppLocalizations localizations,
  SingBoxDegradationKind? kind,
) {
  return switch (kind) {
    SingBoxDegradationKind.nodeProtocol =>
      localizations.singBoxDegradationKindNodeProtocol,
    SingBoxDegradationKind.groupType =>
      localizations.singBoxDegradationKindGroupType,
    SingBoxDegradationKind.groupNested =>
      localizations.singBoxDegradationKindGroupNested,
    SingBoxDegradationKind.groupMember =>
      localizations.singBoxDegradationKindGroupMember,
    SingBoxDegradationKind.groupDropped =>
      localizations.singBoxDegradationKindGroupDropped,
    SingBoxDegradationKind.chain => localizations.singBoxDegradationKindChain,
    SingBoxDegradationKind.routing =>
      localizations.singBoxDegradationKindRouting,
    _ => localizations.singBoxDegradationKindOther,
  };
}

/// Reason strings are renderer templates in one language; this maps each
/// back onto its localized template. An unmatched reason shows verbatim,
/// so renderer drift stays visible instead of being hidden.
String localizedSingBoxDegradationReason(
  AppLocalizations localizations,
  SingBoxDegradation item,
) {
  final reason = item.reason;
  String? capture(RegExp pattern) => pattern.firstMatch(reason)?.group(1);
  switch (item.kind) {
    case SingBoxDegradationKind.nodeProtocol:
      final type = capture(RegExp(r'^协议 (.+) 不在 sing-box 渲染契约内$'));
      if (type != null) {
        return localizations.singBoxDegradationReasonNodeProtocol(type);
      }
    case SingBoxDegradationKind.nodeUnusable:
      if (reason.contains('wireguard 节点缺少本地地址')) {
        return localizations.singBoxDegradationReasonNodeUnusable;
      }
    case SingBoxDegradationKind.groupType:
      final type = capture(RegExp(r'^组类型 (.+) 未承接'));
      if (type != null) {
        return localizations.singBoxDegradationReasonGroupType(type);
      }
    case SingBoxDegradationKind.groupNested:
      if (reason.contains('组成员包含其他组')) {
        return localizations.singBoxDegradationReasonGroupNested;
      }
    case SingBoxDegradationKind.groupMember:
      if (reason.startsWith('REJECT 成员')) {
        return localizations.singBoxDegradationReasonGroupMemberReject;
      }
      final member = capture(RegExp(r'^成员 (.+) 在 sing-box 下不可用'));
      if (member != null) {
        return localizations.singBoxDegradationReasonGroupMember(member);
      }
    case SingBoxDegradationKind.groupDropped:
      if (reason.contains('组内成员全部不可用')) {
        return localizations.singBoxDegradationReasonGroupDropped;
      }
    case SingBoxDegradationKind.chain:
      if (reason.contains('组级 dialer-proxy')) {
        return localizations.singBoxDegradationReasonChainGroup;
      }
      if (reason.contains('链式前置目标')) {
        return localizations.singBoxDegradationReasonChain;
      }
    case SingBoxDegradationKind.routing:
      final count = capture(RegExp(r'^共 (\d+) 条'));
      if (count != null) {
        return localizations.singBoxDegradationReasonRouting(count);
      }
  }
  return reason;
}

/// One-shot, non-blocking: the import has already succeeded by now.
Future<bool?> showSingBoxImportSummary(BuildContext context, int count) {
  final localizations = context.appLocalizations;
  return dialogs.showMessage(
    context: context,
    title: localizations.singBoxDegradationsImportTitle,
    message: TextSpan(
      text: localizations.singBoxDegradationsImportSummary(count),
    ),
    confirmText: localizations.singBoxDegradationsView,
  );
}

/// The named, grouped list in the Hara A reading; no vermilion, because
/// a degradation is not a "current" state.
class SingBoxDegradationsView extends ConsumerWidget {
  const SingBoxDegradationsView({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final localizations = context.appLocalizations;
    // A completed null is the native marker: the profile was never
    // translated, which must not read as an empty ledger.
    final (isNative, items) = switch (ref.watch(
      profileDegradationsProvider(profile.id),
    )) {
      AsyncData(value: final List<SingBoxDegradation> list) => (false, list),
      AsyncData() => (true, const <SingBoxDegradation>[]),
      _ => (false, const <SingBoxDegradation>[]),
    };
    return CommonScaffold(
      title: localizations.singBoxDegradationsTitle,
      body: Material(
        color: palette.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.max(
              HaraSpace.pageInset,
              (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
            );
            return ListView(
              padding: EdgeInsets.symmetric(horizontal: side),
              children: [
                const SizedBox(height: HaraSpace.titleTopGap),
                Text(
                  profile.realLabel,
                  style: HaraText.pageTitle(context, palette.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: HaraSpace.titleToList),
                if (isNative)
                  Text(
                    localizations.singBoxDegradationsNative,
                    style: HaraText.profileMeta(context, palette.sub),
                  )
                else if (items.isEmpty)
                  Text(
                    localizations.singBoxDegradationsAllCarried,
                    style: HaraText.profileMeta(context, palette.sub),
                  )
                else
                  for (final (kind, bucket) in groupSingBoxDegradations(
                    items,
                  )) ...[
                    Row(
                      children: [
                        Text(
                          singBoxDegradationKindTitle(localizations, kind),
                          style: HaraText.sectionTitle(context, palette.dim),
                        ),
                        const SizedBox(width: HaraSpace.sectionTitleGap),
                        Text(
                          '${bucket.length}',
                          style: HaraText.profileMeta(context, palette.dim),
                        ),
                      ],
                    ),
                    const SizedBox(height: HaraSpace.sectionTitleGap),
                    HaraHairline(color: palette.line),
                    for (final item in bucket) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: HaraSpace.nodeRowVertical,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: HaraText.nodeName(
                                context,
                                palette.ink,
                                current: false,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: HaraSpace.profileMetaGap),
                            Text(
                              localizedSingBoxDegradationReason(
                                localizations,
                                item,
                              ),
                              style: HaraText.profileMeta(context, palette.sub),
                            ),
                          ],
                        ),
                      ),
                      HaraHairline(color: palette.line),
                    ],
                    const SizedBox(height: HaraSpace.groupGap),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}
