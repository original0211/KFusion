import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/views/profiles/add.dart';
import 'package:kfusion/views/profiles/profiles.dart';
import 'package:kfusion/views/profiles/singbox_degradations.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

// The Hara A reading of the profiles page: a page title, hairline rows of
// name over two meta lines, and an add section of text rows. The current
// profile carries the screen's single vermilion dot beside its semibold
// name and the in-use word on the right. Rows read and write through the
// same providers and actions as the card grid, including its context menu;
// only the composition is new.
class HaraProfilesView extends ConsumerStatefulWidget {
  const HaraProfilesView({super.key});

  @override
  ConsumerState<HaraProfilesView> createState() => _HaraProfilesViewState();
}

class _HaraProfilesViewState extends ConsumerState<HaraProfilesView> {
  var _isUpdating = false;

  Future<void> _updateAll(List<Profile> profiles) async {
    if (_isUpdating) return;
    _isUpdating = true;
    final messages = await updateUrlProfiles(context, ref, profiles);
    dialogs.showFailures(messages);
    _isUpdating = false;
  }

  void _openSort(List<Profile> profiles) {
    showSheet(
      context: context,
      builder: (_) {
        return ReorderableProfilesSheet(profiles: profiles);
      },
    );
  }

  void _testAll() {
    final groups = ref.read(proxiesListStateProvider).groups;
    final action = ref.read(proxiesActionProvider.notifier);
    for (final group in groups) {
      action.delayTestPageGroup(group.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final state = ref.watch(profilesStateProvider);
    final profiles = state.profiles;
    return Material(
      color: palette.bg,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.max(
              HaraSpace.pageInset,
              (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
            );
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(child: _header(profiles)),
                      if (profiles.isEmpty)
                        const SliverToBoxAdapter(child: _HaraProfilesEmpty())
                      else ...[
                        const SliverToBoxAdapter(
                          child: SizedBox(height: HaraSpace.titleToList),
                        ),
                        SliverToBoxAdapter(
                          child: HaraHairline(color: palette.line),
                        ),
                        SliverList.builder(
                          itemCount: profiles.length,
                          itemBuilder: (context, index) {
                            final profile = profiles[index];
                            return _HaraProfileRow(
                              profile: profile,
                              isCurrent: profile.id == state.currentProfileId,
                            );
                          },
                        ),
                      ],
                      SliverToBoxAdapter(child: _addSection()),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: HaraSpace.modeToNavGap),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(List<Profile> profiles) {
    final palette = context.haraPalette;
    final localizations = context.appLocalizations;
    Widget action(String label, VoidCallback onTap) {
      return InkWell(
        customBorder: AppShape.hara,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: HaraText.pageAction(context, palette.dim)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: HaraSpace.titleTopGap),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  localizations.subscriptions,
                  style: HaraText.pageTitle(context, palette.ink),
                ),
              ),
            ),
            if (profiles.isNotEmpty) ...[
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      action(localizations.actionDelayTest, _testAll),
                      action(localizations.update, () => _updateAll(profiles)),
                      action(
                        localizations.profilesSort,
                        () => _openSort(profiles),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _addSection() {
    final palette = context.haraPalette;
    final localizations = context.appLocalizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: HaraSpace.listToAddGap),
        Text(
          localizations.add,
          style: HaraText.sectionTitle(context, palette.dim),
        ),
        const SizedBox(height: HaraSpace.sectionTitleGap),
        HaraHairline(color: palette.line),
        _HaraAddRow(
          label: localizations.importFromLink,
          onTap: () => showAddProfileFromLinkForm(context, ref),
        ),
        _HaraAddRow(
          label: localizations.file,
          onTap: () => unawaited(
            ref.read(profilesActionProvider.notifier).addProfileFormFile(),
          ),
        ),
        _HaraAddRow(
          label: localizations.more,
          onTap: () => showAddProfilePage(context),
        ),
      ],
    );
  }
}

class _HaraProfilesEmpty extends StatelessWidget {
  const _HaraProfilesEmpty();

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final localizations = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.only(top: 58),
      child: Column(
        children: [
          DiscRingMotif(size: 72, color: palette.dim),
          const SizedBox(height: 20),
          Text(
            localizations.nullTip(localizations.profiles),
            style: HaraText.statusNode(context, palette.sub),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            localizations.nullProfileDesc,
            style: HaraText.profileMeta(context, palette.dim),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HaraAddRow extends StatelessWidget {
  const _HaraAddRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return InkWell(
      customBorder: AppShape.hara,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: HaraSpace.addRowVertical,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: HaraText.addRow(context, palette.sub),
                  ),
                ),
                Text('→', style: HaraText.addRowArrow(context, palette.sub)),
              ],
            ),
          ),
          HaraHairline(color: palette.line),
        ],
      ),
    );
  }
}

class _HaraProfileRow extends ConsumerWidget {
  const _HaraProfileRow({required this.profile, required this.isCurrent});

  final Profile profile;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final isUpdating = ref.watch(isUpdatingProvider(profile.updatingKey));
    return ContextMenuRegion(
      menuItems: isUpdating ? null : profileMenuItems(context, ref, profile),
      child: InkWell(
        customBorder: AppShape.hara,
        onTap: () {
          ref.read(currentProfileIdProvider.notifier).value = profile.id;
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: HaraSpace.profileRowVertical,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isCurrent) ...[
                        const HaraDot(size: HaraSpace.dotRow),
                        const SizedBox(width: HaraSpace.dotNameGap),
                      ],
                      Expanded(
                        child: EmojiText(
                          profile.realLabel,
                          style: HaraText.profileName(
                            context,
                            palette.ink,
                            current: isCurrent,
                          ),
                          maxLines: 1,
                        ),
                      ),
                      if (isCurrent)
                        Text(
                          context.appLocalizations.inUse,
                          style: HaraText.inUse(context, palette.dim),
                        ),
                    ],
                  ),
                  const SizedBox(height: HaraSpace.profileNameToMeta),
                  Text(
                    _metaLine1(context, ref),
                    style: HaraText.profileMeta(context, palette.sub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_hasMetaLine2 || isUpdating) ...[
                    const SizedBox(height: HaraSpace.profileMetaGap),
                    _metaLine2(context, palette, isUpdating: isUpdating),
                  ],
                  ..._degradationEntry(context, ref, palette),
                ],
              ),
            ),
            HaraHairline(color: palette.line),
          ],
        ),
      ),
    );
  }

  String _metaLine1(BuildContext context, WidgetRef ref) {
    final localizations = context.appLocalizations;
    final typeLabel = switch (profile.type) {
      ProfileType.url => localizations.remote,
      ProfileType.file => localizations.local,
      ProfileType.custom => localizations.custom,
    };
    if (profile.type == ProfileType.custom) {
      final count = ref.watch(profileGroupsCountProvider(profile.id)).value;
      if (count != null) {
        return '$typeLabel · ${count.compact}';
      }
    }
    return typeLabel;
  }

  SubscriptionInfo? get _subscriptionInfo =>
      profile.type == ProfileType.url ? profile.subscriptionInfo : null;

  List<String> get _metaParts {
    final parts = <String>[];
    final info = _subscriptionInfo;
    if (info != null && info.usage != null) {
      final used = info.upload + info.download;
      parts.add('${used.traffic.show} / ${info.total.traffic.show}');
    }
    final expire = _subscriptionInfo?.expireDate;
    if (expire != null) {
      parts.add(expire.show);
    }
    return parts;
  }

  bool get _hasMetaLine2 =>
      _metaParts.isNotEmpty || profile.lastUpdateDate != null;

  Widget _metaLine2(
    BuildContext context,
    HaraPalette palette, {
    required bool isUpdating,
  }) {
    final style = HaraText.profileMeta(context, palette.dim);
    final parts = _metaParts;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, part) in parts.indexed) ...[
            if (index > 0) Text(' · ', style: style),
            Text(part, style: style),
          ],
          if (profile.lastUpdateDate != null) ...[
            if (parts.isNotEmpty) Text(' · ', style: style),
            if (isUpdating)
              const CommonCircleLoading(size: 14)
            else
              LastUpdateTimeText(
                lastUpdateDate: profile.lastUpdateDate,
                style: style,
                compact: true,
              ),
          ] else if (isUpdating) ...[
            if (parts.isNotEmpty) Text(' · ', style: style),
            const CommonCircleLoading(size: 14),
          ],
        ],
      ),
    );
  }

  // Absent while the ledger loads and when nothing degrades.
  List<Widget> _degradationEntry(
    BuildContext context,
    WidgetRef ref,
    HaraPalette palette,
  ) {
    final items = ref.watch(profileDegradationsProvider(profile.id)).value;
    if (items == null || items.isEmpty) return const [];
    return [
      const SizedBox(height: HaraSpace.profileMetaGap),
      InkWell(
        customBorder: AppShape.hara,
        onTap: () {
          BaseNavigator.push(
            context,
            SingBoxDegradationsView(profile: profile),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.appLocalizations.singBoxDegradationsCount(items.length),
              style: HaraText.profileMeta(context, palette.sub),
            ),
            const SizedBox(width: 6),
            Text('→', style: HaraText.addRowArrow(context, palette.sub)),
          ],
        ),
      ),
    ];
  }
}
