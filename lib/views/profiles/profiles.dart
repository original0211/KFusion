import 'dart:async';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/profiles/custom/custom.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add.dart';
import 'edit.dart';
import 'hara_profiles.dart';
import 'preview.dart';

/// Updates every url profile in [profiles] and returns the failures, the
/// same run the profiles pages' update action performs.
Future<List<UpdatingMessage>> updateUrlProfiles(
  BuildContext context,
  WidgetRef ref,
  List<Profile> profiles,
) async {
  final appLocalizations = context.appLocalizations;
  final profilesAction = ref.read(profilesActionProvider.notifier);
  final List<UpdatingMessage> messages = [];
  final updates = profiles.map<Future>((profile) async {
    if (profile.type != ProfileType.url) return;
    try {
      await profilesAction.updateProfile(profile, showLoading: true);
    } catch (e) {
      messages.add(
        UpdatingMessage(
          label: profile.realLabel,
          message: userFacingErrorMessage(e, appLocalizations),
        ),
      );
    }
  });
  await Future.wait(updates);
  return messages;
}

const _infoGap = 4.0;

double get _profileItemHeight {
  final measure = globalState.measure;
  return measure.textHeight(AppTextStyle.headline) +
      _infoGap +
      measure.textHeight(AppTextStyle.footnote) +
      2 * listRowVerticalPadding;
}

class ProfilesView extends ConsumerStatefulWidget {
  const ProfilesView({super.key, this.picker = false});

  /// Clears the bar and opens at the top, for switching profiles from a sheet.
  final bool picker;

  @override
  ConsumerState<ProfilesView> createState() => _ProfilesViewState();
}

class _ProfilesViewState extends ConsumerState<ProfilesView> {
  bool _isUpdating = false;

  Future<void> _updateProfiles(List<Profile> profiles) async {
    if (_isUpdating == true) {
      return;
    }
    _isUpdating = true;
    final messages = await updateUrlProfiles(context, ref, profiles);
    dialogs.showFailures(messages);
    _isUpdating = false;
  }

  List<IconButtonData> _buildActions(List<Profile> profiles) {
    return profiles.isNotEmpty
        ? [
            IconButtonData(
              glyph: AppGlyphs.sync,
              onPressed: () {
                _updateProfiles(profiles);
              },
              tooltip: context.appLocalizations.update,
            ),
            IconButtonData(
              glyph: AppGlyphs.sort,
              onPressed: () {
                showSheet(
                  context: context,
                  builder: (_) {
                    return ReorderableProfilesSheet(profiles: profiles);
                  },
                );
              },
              tooltip: context.appLocalizations.profilesSort,
            ),
          ]
        : [];
  }

  @override
  Widget build(BuildContext context) {
    // The main navigation entry reads in the Hara A composition; the picker
    // keeps the card grid inside its sheet.
    if (!widget.picker) {
      return const HaraProfilesView();
    }
    return Consumer(
      builder: (_, ref, _) {
        final appLocalizations = context.appLocalizations;
        final isLoading = ref.watch(loadingProvider(LoadingTag.profiles));
        final state = ref.watch(profilesStateProvider);
        final spacing = cardSpacingOf(context, ref.watch(viewModeProvider));
        final picker = widget.picker;
        return CommonScaffold(
          isLoading: isLoading,
          title: appLocalizations.profiles,
          primaryAction: state.profiles.isEmpty || picker
              ? null
              : IconButtonData(
                  glyph: AppGlyphs.addCircle,
                  onPressed: () => showAddProfilePage(context),
                  tooltip: appLocalizations.addProfile,
                ),
          iconActions: picker ? const [] : _buildActions(state.profiles),
          foldPrimaryAction: true,
          body: NullStatusSwitcher(
            isEmpty: state.profiles.isEmpty,
            nullStatus: NullStatus.brand(
              label: appLocalizations.nullTip(appLocalizations.profiles),
              description: appLocalizations.nullProfileDesc,
              action: TonalButton(
                size: TonalButtonSize.bar,
                glyph: AppGlyphs.addCircle,
                label: appLocalizations.addProfile,
                onPressed: () => showAddProfilePage(context),
              ),
            ),
            child: _ProfilesGrid(
              profiles: state.profiles,
              currentProfileId: state.currentProfileId,
              spacing: spacing,
              revealsSelected: !picker,
            ),
          ),
        );
      },
    );
  }
}

class _ProfilesGrid extends ConsumerStatefulWidget {
  const _ProfilesGrid({
    required this.profiles,
    required this.currentProfileId,
    required this.spacing,
    required this.revealsSelected,
  });

  final List<Profile> profiles;
  final int? currentProfileId;
  final double spacing;
  final bool revealsSelected;

  @override
  ConsumerState<_ProfilesGrid> createState() => _ProfilesGridState();
}

class _ProfilesGridState extends ConsumerState<_ProfilesGrid> {
  static const _horizontalPadding = 16.0;

  late final ScrollController _controller;
  var _revealed = false;

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_revealed ||
        !widget.revealsSelected ||
        !PageActivityScope.isActiveOf(context)) {
      return;
    }
    _revealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  EdgeInsets get _padding => EdgeInsets.only(
    left: _horizontalPadding,
    right: _horizontalPadding,
    top: context.contentTopPadding,
    bottom: 16 + BottomInsetScope.of(context),
  );

  int _columnsFor(double width) => getProfilesColumns(
    width - _horizontalPadding * 2,
    spacing: widget.spacing,
    minItemWidth: profileItemMinWidth.ap(context),
  );

  void _revealSelected() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final index = widget.profiles.indexWhere(
      (profile) => profile.id == widget.currentProfileId,
    );
    if (index == -1) {
      return;
    }
    final position = _controller.position;
    final padding = _padding;
    final height = _profileItemHeight;
    final row = index ~/ _columnsFor(context.size!.width);
    final atTop = row * (height + widget.spacing);
    final atBottom =
        atTop + padding.vertical + height - position.viewportDimension;
    if (position.pixels >= atBottom && position.pixels <= atTop) {
      return;
    }
    _controller.jumpTo(
      ((atTop + atBottom) / 2).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.profiles;
    return WidthBuilder(
      builder: (_, width) {
        return GridView.builder(
          key: profilesStoreKey,
          controller: _controller,
          padding: _padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columnsFor(width),
            mainAxisSpacing: widget.spacing,
            crossAxisSpacing: widget.spacing,
            mainAxisExtent: _profileItemHeight,
          ),
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final profile = profiles[index];
            return ProfileItem(
              key: ValueKey(profile.id),
              profile: profile,
              groupValue: widget.currentProfileId,
              onChanged: (profileId) {
                ref.read(currentProfileIdProvider.notifier).value = profileId;
              },
            );
          },
        );
      },
    );
  }
}

/// The profile row actions, shared by the card grid and the Hara A list.
Future<void> confirmDeleteProfile(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final profilesAction = ref.read(profilesActionProvider.notifier);
  final appLocalizations = context.appLocalizations;
  final users = await profilesAction.providerUsers(profile);
  final res = await dialogs.showMessage(
    title: appLocalizations.tip,
    message: TextSpan(
      text: users.isEmpty
          ? appLocalizations.deleteTip(appLocalizations.profile)
          : appLocalizations.providerInUse(
              profile.realLabel,
              users.map((item) => item.realLabel).join(', '),
            ),
    ),
    destructive: true,
    confirmText: appLocalizations.delete,
  );
  if (res != true) {
    return;
  }
  await profilesAction.deleteProfile(profile.id);
}

void previewProfile(BuildContext context, Profile profile) {
  unawaited(
    BaseNavigator.push<String>(context, PreviewProfileView(profile: profile)),
  );
}

Future<void> syncProfile(WidgetRef ref, Profile profile) async {
  if (profile.type != ProfileType.url) return;
  await globalState.loadingRun(() async {
    await ref
        .read(profilesActionProvider.notifier)
        .updateProfile(profile, showLoading: true);
  }, tag: LoadingTag.profiles);
}

void editProfileEntry(BuildContext context, Profile profile) {
  if (profile.type == ProfileType.custom) {
    BaseNavigator.push(context, CustomProfileView(profileId: profile.id));
    return;
  }
  showExtend(context, builder: (context) => EditProfileView(profile: profile));
}

Future<void> copyProfileLink(BuildContext context, Profile profile) async {
  await Clipboard.setData(ClipboardData(text: profile.url));
  if (context.mounted) {
    context.showNotifier(
      context.appLocalizations.copySuccess,
      level: MessageLevel.success,
    );
  }
}

Future<void> exportProfileFile(BuildContext context, Profile profile) async {
  final appLocalizations = context.appLocalizations;
  final res = await globalState.safeRun<bool>(() async {
    final mFile = await profile.file;
    final value = await picker.saveFile(
      profile.exportFileName,
      mFile.readAsBytesSync(),
    );
    if (value == null) return false;
    return true;
  }, title: appLocalizations.tip);
  if (res == true && context.mounted) {
    context.showNotifier(
      appLocalizations.exportSuccess,
      level: MessageLevel.success,
    );
  }
}

List<CommonPopupMenuItem> profileMenuItems(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) {
  final appLocalizations = context.appLocalizations;
  final isUrl = profile.type == ProfileType.url;
  final isCustom = profile.type == ProfileType.custom;
  return [
    CommonPopupMenuItem(
      glyph: AppGlyphs.edit,
      // A custom profile's editor group is an advanced surface: its menu
      // door says so, where a plain profile keeps the plain edit door.
      label: isCustom ? appLocalizations.advancedEdit : appLocalizations.edit,
      onPressed: () => editProfileEntry(context, profile),
    ),
    if (isCustom) ...[
      CommonPopupMenuItem(
        glyph: AppGlyphs.textShort,
        label: appLocalizations.rename,
        onPressed: () {
          renameProfile(context, ref, profile);
        },
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.eye,
        label: appLocalizations.runtimeConfig,
        onPressed: () {
          previewProfile(context, profile);
        },
      ),
    ],
    if (isUrl)
      CommonPopupMenuItem(
        glyph: AppGlyphs.sync,
        label: appLocalizations.sync,
        onPressed: () {
          syncProfile(ref, profile);
        },
      ),
    if (!isCustom)
      CommonPopupMenuItem(
        glyph: AppGlyphs.moreCircle,
        label: appLocalizations.more,
        subItems: [
          CommonPopupMenuItem(
            glyph: AppGlyphs.eye,
            label: appLocalizations.runtimeConfig,
            onPressed: () {
              previewProfile(context, profile);
            },
          ),
          if (isUrl)
            CommonPopupMenuItem(
              glyph: AppGlyphs.copy,
              label: appLocalizations.copyLink,
              onPressed: () {
                copyProfileLink(context, profile);
              },
            ),
          CommonPopupMenuItem(
            glyph: AppGlyphs.export,
            label: appLocalizations.exportFile,
            onPressed: () {
              exportProfileFile(context, profile);
            },
          ),
        ],
      ),
    CommonPopupMenuItem(
      danger: true,
      glyph: AppGlyphs.delete,
      label: appLocalizations.delete,
      onPressed: () {
        confirmDeleteProfile(context, ref, profile);
      },
    ),
  ];
}

class ProfileItem extends ConsumerWidget {
  final Profile profile;
  final int? groupValue;
  final void Function(int? value) onChanged;

  const ProfileItem({
    super.key,
    required this.profile,
    required this.groupValue,
    required this.onChanged,
  });

  List<CommonPopupMenuItem> _menuItems(BuildContext context, WidgetRef ref) {
    return profileMenuItems(context, ref, profile);
  }

  SubscriptionInfo? get _subscriptionInfo =>
      profile.type == ProfileType.url ? profile.subscriptionInfo : null;

  String _subtitle(BuildContext context) {
    final info = _subscriptionInfo;
    if (info != null && info.usage != null) {
      final used = info.upload + info.download;
      return '${used.traffic.show} / ${info.total.traffic.show}';
    }
    final appLocalizations = context.appLocalizations;
    return switch (profile.type) {
      ProfileType.url => appLocalizations.remote,
      ProfileType.file => appLocalizations.local,
      ProfileType.custom => appLocalizations.custom,
    };
  }

  Widget _buildTrailing(BuildContext context, {required bool isUpdating}) {
    return AnimatedSwitcher(
      duration: context.motionDuration(commonDuration),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: AlignmentDirectional.centerEnd,
        children: [...previousChildren, ?currentChild],
      ),
      child: isUpdating
          ? const CommonCircleLoading(key: ValueKey('updating'), size: 24)
          : LastUpdateTimeText(
              key: const ValueKey('lastUpdate'),
              lastUpdateDate: profile.lastUpdateDate,
              style: AppTextStyle.footnote.of(context).toLighter,
              compact: true,
            ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUpdating = ref.watch(isUpdatingProvider(profile.updatingKey));
    final subscriptionInfo = _subscriptionInfo;
    final isSelected = profile.id == groupValue;
    final colorScheme = context.colorScheme;
    return ContextMenuRegion(
      menuItems: isUpdating ? null : _menuItems(context, ref),
      child: CommonCard(
        enterActionsOnRight: true,
        radius: AppCorner.xl,
        isSelected: isSelected,
        onPressed: () {
          onChanged(profile.id);
        },
        child: Stack(
          children: [
            if (isSelected)
              PositionedDirectional(
                end: -46,
                top: -58,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.045,
                    child: DashboardDiscMotif(
                      size: 128,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ListItem(
              key: Key(profile.id.toString()),
              minTileHeight: _profileItemHeight,
              minVerticalPadding: listRowVerticalPadding,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  if (profile.type == ProfileType.custom)
                    _GroupsCountChip(profileId: profile.id)
                  else
                    _buildTrailing(context, isUpdating: isUpdating),
                  if (isSelected)
                    MetaChip(
                      label: context.appLocalizations.inUse,
                      color: colorScheme.primary,
                    ),
                ],
              ),
              title: _ProfileCardTitle(
                profile: profile,
                expire: subscriptionInfo?.expireDate,
                subtitle: _subtitle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCardTitle extends StatelessWidget {
  const _ProfileCardTitle({
    required this.profile,
    required this.expire,
    required this.subtitle,
  });

  final Profile profile;
  final DateTime? expire;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChipTitle(
          title: profile.realLabel,
          expire: expire,
          style: AppTextStyle.headline.of(context),
        ),
        const SizedBox(height: _infoGap),
        Text(
          subtitle,
          style: AppTextStyle.footnote.of(context).toLighter,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Square-cornered so a lone digit never reads as a second [SelectionBadge].
class _GroupsCountChip extends ConsumerWidget {
  const _GroupsCountChip({required this.profileId});

  final int profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(profileGroupsCountProvider(profileId)).value;
    if (count == null) {
      return const SizedBox.shrink();
    }
    final colorScheme = context.colorScheme;
    return Tooltip(
      message: context.appLocalizations.proxyGroupsCount(count, count.compact),
      child: TonalChip(
        label: count.compact,
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        foregroundColor: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class ReorderableProfilesSheet extends ConsumerStatefulWidget {
  final List<Profile> profiles;

  const ReorderableProfilesSheet({super.key, required this.profiles});

  @override
  ConsumerState<ReorderableProfilesSheet> createState() =>
      _ReorderableProfilesSheetState();
}

class _ReorderableProfilesSheetState
    extends ConsumerState<ReorderableProfilesSheet> {
  late List<Profile> profiles;

  @override
  void initState() {
    super.initState();
    profiles = List.from(widget.profiles);
  }

  Widget _buildItem(int index) {
    final position = ItemPosition.get(index, profiles.length);
    final profile = profiles[index];
    return ItemPositionProvider(
      key: Key(profile.id.toString()),
      position: position,
      child: DecorationListItem(
        contentPadding: const EdgeInsets.only(left: 16),
        trailing: SortHandle(index: index),
        title: Text(profile.realLabel),
      ),
    );
  }

  void _handleSave() {
    Navigator.of(context).pop();
    final latest = ref.read(profilesProvider);
    final ids = {for (final profile in profiles) profile.id};
    ref.read(profilesProvider.notifier).reorder([
      for (final profile in profiles) ?latest.getProfile(profile.id),
      for (final profile in latest)
        if (!ids.contains(profile.id)) profile,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      confirmationAction: IconButtonData(
        glyph: AppGlyphs.check,
        onPressed: _handleSave,
        tooltip: context.appLocalizations.save,
      ),
      body: Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(top: context.contentTopPadding),
          proxyDecorator: (child, index, animation) {
            return commonProxyDecorator(_buildItem(index), index, animation);
          },
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              profiles = profiles.copyAndReorder(oldIndex, newIndex);
            });
          },
          itemBuilder: (_, index) {
            return _buildItem(index);
          },
          itemCount: profiles.length,
        ),
      ),
      title: appLocalizations.profilesSort,
    );
  }
}
