import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/dns.dart';
import 'package:kfusion/views/config/network.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

class AdvancedConfigView extends StatelessWidget {
  const AdvancedConfigView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    return BaseScaffold(
      title: appLocalizations.advancedConfig,
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
                  label: appLocalizations.network,
                  target: BaseScaffold(
                    title: appLocalizations.network,
                    body: const NetworkListView(),
                  ),
                ),
                const _HaraOpenRow(label: 'DNS', target: DnsView()),
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
