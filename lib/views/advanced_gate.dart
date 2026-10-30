import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/views/config/advanced.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/developer.dart';
import 'package:kfusion/views/logs.dart';
import 'package:kfusion/views/proxies/setting.dart';
import 'package:kfusion/views/resources.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one door the settings page keeps to everything the screen plan
/// retired from daily reach: the pages behind it keep their existing
/// shape and are reached only from here (the developer page keeps its
/// developer-mode condition).
class AdvancedGateView extends ConsumerWidget {
  const AdvancedGateView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final developerMode = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    return BaseScaffold(
      title: appLocalizations.advanced,
      body: Material(
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
                HaraHairline(color: palette.line),
                _HaraOpenRow(
                  label: appLocalizations.advancedConfig,
                  target: const AdvancedConfigView(),
                ),
                _HaraOpenRow(
                  label: appLocalizations.general,
                  target: const GeneralView(),
                ),
                _HaraOpenRow(
                  label: appLocalizations.proxySettings,
                  target: BaseScaffold(
                    title: appLocalizations.proxySettings,
                    body: const ProxiesSetting(),
                  ),
                ),
                _HaraOpenRow(
                  label: appLocalizations.resources,
                  target: const ResourcesView(),
                ),
                _HaraOpenRow(
                  label: appLocalizations.logs,
                  target: const LogsView(),
                ),
                if (developerMode)
                  _HaraOpenRow(
                    label: appLocalizations.developerMode,
                    target: const DeveloperView(),
                  ),
              ],
            );
          },
        ),
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

/// A row that opens a page: an ink label and a sub arrow. The open
/// follows the list row it replaces — sheet push or open container.
class _HaraOpenRow extends StatelessWidget {
  const _HaraOpenRow({required this.label, required this.target});

  final String label;
  final Widget target;

  Widget _content(BuildContext context) {
    final palette = context.haraPalette;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: HaraText.nodeName(context, palette.ink, current: false),
          ),
        ),
        Text('→', style: HaraText.addRowArrow(context, palette.sub)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    if (!context.isMobileView) {
      return _HaraRow(
        onTap: () {
          showExtend<dynamic>(
            context,
            props: const ExtendProps(forceFull: true),
            builder: (_) => target,
          );
        },
        child: _content(context),
      );
    }
    return OpenContainer<dynamic>(
      clipBehavior: Clip.none,
      closedColor: palette.bg,
      closedShape: AppShape.hara,
      closedBuilder: (context, action) {
        return _HaraRow(onTap: action, child: _content(context));
      },
      openBuilder: (_, _) => target,
    );
  }
}
