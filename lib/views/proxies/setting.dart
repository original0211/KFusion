import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProxiesSetting extends ConsumerWidget {
  const ProxiesSetting({super.key});

  static ConfigWriter<T> _writer<T>(
    ProxiesStyleProps Function(ProxiesStyleProps state, T value) update,
  ) {
    return (ref, value) => ref
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => update(state, value));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final isList = ref.watch(
      proxiesStyleSettingProvider.select(
        (state) => state.type == ProxiesType.list,
      ),
    );
    final sections = <Widget>[
      HaraSection(
        title: appLocalizations.proxySettings,
        rows: [
          HaraOptions<ProxiesType>(
            ConfigOptionsItem<ProxiesType>(
              title: (l) => l.style,
              options: ProxiesType.values,
              textBuilder: (type) => type.label,
              selector: proxiesStyleSettingProvider.select(
                (state) => state.type,
              ),
              onChanged: _writer((state, value) => state.copyWith(type: value)),
            ),
          ),
          HaraOptions<ProxiesSortType>(
            ConfigOptionsItem<ProxiesSortType>(
              title: (l) => l.sort,
              options: ProxiesSortType.values,
              textBuilder: (type) => switch (type) {
                ProxiesSortType.none => appLocalizations.defaultText,
                ProxiesSortType.delay => appLocalizations.delay,
                ProxiesSortType.name => appLocalizations.name,
              },
              selector: proxiesStyleSettingProvider.select(
                (state) => state.sortType,
              ),
              onChanged: _writer(
                (state, value) => state.copyWith(sortType: value),
              ),
            ),
          ),
          HaraOptions<ProxiesLayout>(
            ConfigOptionsItem<ProxiesLayout>(
              title: (l) => l.layout,
              options: ProxiesLayout.values,
              textBuilder: (layout) => switch (layout) {
                ProxiesLayout.tight => appLocalizations.tight,
                ProxiesLayout.standard => appLocalizations.standard,
                ProxiesLayout.loose => appLocalizations.loose,
              },
              selector: proxiesStyleSettingProvider.select(
                (state) => state.layout,
              ),
              onChanged: _writer(
                (state, value) => state.copyWith(layout: value),
              ),
            ),
          ),
          HaraOptions<ProxyCardType>(
            ConfigOptionsItem<ProxyCardType>(
              title: (l) => l.size,
              options: ProxyCardType.values,
              textBuilder: (type) => type.label,
              selector: proxiesStyleSettingProvider.select(
                (state) => state.cardType,
              ),
              onChanged: _writer(
                (state, value) => state.copyWith(cardType: value),
              ),
            ),
          ),
          if (isList)
            HaraOptions<ProxiesIconStyle>(
              ConfigOptionsItem<ProxiesIconStyle>(
                title: (l) => l.iconStyle,
                options: ProxiesIconStyle.values,
                textBuilder: (style) => switch (style) {
                  ProxiesIconStyle.filled => appLocalizations.iconStyleFilled,
                  ProxiesIconStyle.plain => appLocalizations.iconStylePlain,
                  ProxiesIconStyle.hidden => appLocalizations.iconStyleHidden,
                },
                selector: proxiesStyleSettingProvider.select(
                  (state) => state.iconStyle,
                ),
                onChanged: _writer(
                  (state, value) => state.copyWith(iconStyle: value),
                ),
              ),
            ),
        ],
      ),
      HaraSection(
        title: appLocalizations.filter,
        footer: appLocalizations.hideTimeoutProxiesDesc,
        rows: [
          HaraToggle(
            ConfigToggleItem(
              title: (l) => l.hideTimeoutProxies,
              selector: proxiesStyleSettingProvider.select(
                (state) => state.hideTimeoutProxies,
              ),
              onChanged: _writer(
                (state, value) => state.copyWith(hideTimeoutProxies: value),
              ),
            ),
          ),
        ],
      ),
    ];
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
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) const SizedBox(height: HaraSpace.groupGap),
                sections[i],
              ],
            ],
          );
        },
      ),
    );
  }
}
