import 'dart:async';

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
    final appLocalizations = context.appLocalizations;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
      ).copyWith(top: context.contentTopPadding, bottom: 16),
      children: [
        generateSection(
          items: [
            ListItem(
              leading: const GlyphIcon(AppGlyphs.qrCode),
              title: Text(appLocalizations.qrcode),
              subtitle: Text(appLocalizations.qrcodeDesc),
              onTap: () => _toScan(ref),
            ),
            ListItem(
              leading: const GlyphIcon(AppGlyphs.importFile),
              title: Text(appLocalizations.file),
              subtitle: Text(appLocalizations.fileDesc),
              onTap: () => _handleAddProfileFormFile(ref),
            ),
            ListItem(
              leading: const GlyphIcon(AppGlyphs.cloudDownload),
              title: Text(appLocalizations.link),
              subtitle: Text(appLocalizations.linkDesc),
              onTap: () => _toAdd(ref),
            ),
            ListItem(
              leading: GlyphIcon(
                AppGlyphs.sparkle,
                color: context.colorScheme.primary,
              ),
              title: const Text('万能导入'),
              subtitle: const Text('Clash / sing-box / 分享链接 / 订阅，一次导入'),
              onTap: () =>
                  BaseNavigator.push(context, const UniversalImportView()),
            ),
          ],
        ),
      ],
    );
  }
}
