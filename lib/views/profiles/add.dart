import 'dart:async';
import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/pages/scan.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/profiles/universal_import.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The link import form behind the add page's link entry, shared with the
/// profiles page's own add rows.
Future<void> showAddProfileFromLinkForm(
  BuildContext context,
  WidgetRef ref,
) async {
  final profilesAction = ref.read(profilesActionProvider.notifier);
  final appLocalizations = context.appLocalizations;
  final res = await showNamedUrlsForm(
    context,
    title: appLocalizations.importFromLink,
    urlLabel: appLocalizations.link,
    batchTip: appLocalizations.batchLinkInputTip,
    urlValidator: (value) {
      if (value == null || value.isEmpty) {
        return appLocalizations.emptyTip(appLocalizations.link);
      }
      if (!value.isUrl && !value.isShareLink) {
        return appLocalizations.invalidLinkTip;
      }
      return null;
    },
    existingUrls: {
      for (final profile in ref.read(profilesProvider))
        if (profile.url.isNotEmpty) profile.url,
    },
    withAgeSecretKey: true,
  );
  switch (res) {
    case null:
      return;
    case [final single]:
      unawaited(
        profilesAction.addProfileFromLink(
          single.url,
          label: single.label,
          ageSecretKey: single.ageSecretKey,
        ),
      );
    default:
      unawaited(
        profilesAction.addProfilesFromLinks([for (final item in res) item.url]),
      );
  }
}

void showAddProfilePage(BuildContext origin) {
  final context = globalState.navigatorKey.currentState!.context;
  showExtend(
    context,
    builder: (context) => CommonScaffold(
      title: context.appLocalizations.addProfile,
      body: AddProfileView(context: context, origin: origin),
    ),
  );
}

class AddProfileView extends ConsumerWidget {
  final BuildContext context;

  /// Where a page the add page leads to opens: the desktop sheet is on the root.
  final BuildContext origin;

  const AddProfileView({
    super.key,
    required this.context,
    required this.origin,
  });

  Future<void> _handleAddProfileFormFile(WidgetRef ref) async {
    unawaited(ref.read(profilesActionProvider.notifier).addProfileFormFile());
  }

  Future<void> _toScan(WidgetRef ref) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    if (system.isDesktop) {
      unawaited(profilesAction.addProfileFormQrCode());
      return;
    }
    final url = await BaseNavigator.push(context, const ScanPage());
    if (url != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(profilesAction.addProfileFromLink(url));
      });
    }
  }

  Future<void> _toAdd(WidgetRef ref) async {
    await showAddProfileFromLinkForm(context, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    return Material(
      color: palette.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = max(
            HaraSpace.pageInset,
            (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(side, context.appBarInset, side, 48),
            children: [
              _HaraSection(
                rows: [
                  _HaraEntryRow(
                    glyph: AppGlyphs.qrCode,
                    title: appLocalizations.qrcode,
                    subtitle: appLocalizations.qrcodeDesc,
                    onTap: () => _toScan(ref),
                  ),
                  _HaraEntryRow(
                    glyph: AppGlyphs.importFile,
                    title: appLocalizations.file,
                    subtitle: appLocalizations.fileDesc,
                    onTap: () => _handleAddProfileFormFile(ref),
                  ),
                  _HaraEntryRow(
                    glyph: AppGlyphs.cloudDownload,
                    title: appLocalizations.link,
                    subtitle: appLocalizations.linkDesc,
                    onTap: () => _toAdd(ref),
                  ),
                  _HaraEntryRow(
                    glyph: AppGlyphs.sparkle,
                    title: '万能导入',
                    subtitle: 'Clash / sing-box / 分享链接 / 订阅，一次导入',
                    onTap: () => BaseNavigator.push(
                      context,
                      const UniversalImportView(),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One hairline row of the page: content over a bottom hairline.
class _HaraRow extends StatelessWidget {
  const _HaraRow({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: HaraSpace.nodeRowVertical,
          ),
          child: child,
        ),
        HaraHairline(color: palette.line),
      ],
    );
    if (onTap == null) return content;
    return InkWell(customBorder: AppShape.hara, onTap: onTap, child: content);
  }
}

/// A section of the page: a hairline and its rows.
class _HaraSection extends StatelessWidget {
  const _HaraSection({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HaraHairline(color: palette.line),
        ...rows,
      ],
    );
  }
}

/// One add entry: a glyph, its name and its one-line description; the
/// whole row is the tap target, as the list item it replaces was.
class _HaraEntryRow extends StatelessWidget {
  const _HaraEntryRow({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Glyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return _HaraRow(
      onTap: onTap,
      child: Row(
        children: [
          GlyphIcon(glyph, color: palette.sub),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: HaraText.nodeName(
                    context,
                    palette.ink,
                    current: false,
                  ),
                ),
                const SizedBox(height: HaraSpace.profileMetaGap),
                Text(
                  subtitle,
                  style: HaraText.profileMeta(context, palette.sub),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
