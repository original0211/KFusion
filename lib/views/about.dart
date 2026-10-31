import 'dart:async';
import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kfusion/widgets/hara_rows.dart';

class AboutView extends ConsumerWidget {
  const AboutView({super.key});

  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    if (ref.read(loadingProvider(LoadingTag.checkUpdate))) return;
    final commonAction = ref.read(commonActionProvider.notifier);
    final result = await globalState.loadingRun(
      () async => (release: await request.checkForUpdate()),
      title: context.appLocalizations.checkUpdate,
      tag: LoadingTag.checkUpdate,
    );
    if (result == null) return;
    unawaited(
      commonAction.checkUpdateResultHandle(data: result.release, isUser: true),
    );
  }

  Widget _buildLinkItem({
    required String title,
    required String url,
    required String label,
  }) {
    return Builder(
      builder: (context) {
        final palette = context.haraPalette;
        return HaraRow(
          onTap: () {
            dialogs.openUrl(url);
          },
          child: Row(
            children: [
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
                      label,
                      style: HaraText.payload(context, palette.sub),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text('→', style: HaraText.addRowArrow(context, palette.sub)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    final isLoading = ref.watch(loadingProvider(LoadingTag.checkUpdate));
    return CommonScaffold(
      isLoading: isLoading,
      title: appLocalizations.about,
      body: Material(
        color: palette.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.max(
              HaraSpace.pageInset,
              (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
            );
            return ListView(
              padding: EdgeInsets.fromLTRB(
                side,
                context.contentTopPadding,
                side,
                48,
              ),
              children: [
                _AboutHero(
                  isCheckingUpdate: isLoading,
                  onCheckUpdate: () {
                    _checkUpdate(context, ref);
                  },
                ),
                const SizedBox(height: HaraSpace.groupGap),
                _section(
                  context,
                  appLocalizations.more,
                  rows: [
                    _buildLinkItem(
                      title: appLocalizations.project,
                      url: 'https://github.com/$repository',
                      label: 'github.com/$repository',
                    ),
                    _buildLinkItem(
                      title: appLocalizations.core,
                      url: 'https://github.com/MetaCubeX/Clash.Meta',
                      label: 'github.com/MetaCubeX/Clash.Meta',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Widget _section(
  BuildContext context,
  String title, {
  required List<Widget> rows,
}) {
  final palette = context.haraPalette;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: HaraText.sectionTitle(context, palette.sub)),
      const SizedBox(height: HaraSpace.sectionTitleGap),
      HaraHairline(color: palette.line),
      ...rows,
    ],
  );
}

class _AboutHero extends StatelessWidget {
  final bool isCheckingUpdate;
  final VoidCallback onCheckUpdate;

  const _AboutHero({
    required this.isCheckingUpdate,
    required this.onCheckUpdate,
  });

  static const _logoSize = 96.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    return Column(
      children: [
        Image.asset(
          Theme.of(context).brightness == Brightness.dark
              ? 'assets/images/icon_dark.png'
              : 'assets/images/icon.png',
          width: _logoSize,
          height: _logoSize,
        ),
        const SizedBox(height: 20),
        Text(appName, style: HaraText.pageTitle(context, palette.ink)),
        const SizedBox(height: 10),
        Text(
          'v${globalState.packageInfo.version} · GPL-3.0',
          style: HaraText.profileMeta(context, palette.sub),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            appLocalizations.desc,
            textAlign: TextAlign.center,
            style: HaraText.profileMeta(
              context,
              palette.sub,
            ).copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          button: true,
          enabled: !isCheckingUpdate,
          child: InkWell(
            customBorder: AppShape.hara,
            onTap: isCheckingUpdate ? null : onCheckUpdate,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                appLocalizations.checkUpdate,
                style: HaraText.action(
                  context,
                  isCheckingUpdate ? palette.dim : palette.ink,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
