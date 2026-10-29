import 'package:kfusion/common/common.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/about.dart';
import 'package:kfusion/views/access.dart';
import 'package:kfusion/views/advanced_gate.dart';
import 'package:kfusion/views/backup_and_restore.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/config/network.dart';
import 'package:kfusion/views/hotkey.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'disclaimer.dart';
import 'theme.dart';

class ToolsView extends ConsumerStatefulWidget {
  const ToolsView({super.key});

  @override
  ConsumerState<ToolsView> createState() => _ToolViewState();
}

class _ToolViewState extends ConsumerState<ToolsView> {
  // The takeover masters; their detail rows stay on the network page.
  List<Widget> _takeoverItems() {
    if (system.isAndroid) {
      return const [VPNItem(), VpnSystemProxyItem()];
    }
    if (system.isDesktop) {
      return const [SystemProxyItem(), TUNItem()];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final items = [
      generateSection(items: const [CoreSwitchItem()]),
      generateSection(
        title: appLocalizations.startupAndBackground,
        items: startupSettingItems(),
        footer: [
          if (system.isDesktop) appLocalizations.silentLaunchDesc,
          appLocalizations.autoRunDesc,
        ].join('\n'),
      ),
      generateSection(items: _takeoverItems()),
      generateSection(
        items: [
          const _LocaleItem(),
          const _ThemeItem(),
          const _BackupItem(),
          if (system.isDesktop) const _HotkeyItem(),
          if (system.isAndroid) const _AccessItem(),
        ],
      ),
      generateSection(items: const [_AdvancedGateItem()]),
      generateSection(items: const [_DisclaimerItem(), _InfoItem()]),
    ];
    return CommonScaffold(
      title: appLocalizations.settings,
      body: Builder(
        builder: (context) => ListView.builder(
          key: toolsStoreKey,
          itemCount: items.length,
          itemBuilder: (_, index) => items[index],
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: context.appBarInset,
            bottom: 20 + BottomInsetScope.of(context),
          ),
        ),
      ),
    );
  }
}

class _LocaleItem extends ConsumerWidget {
  const _LocaleItem();

  String _getLocaleString(BuildContext context, Locale? locale) {
    if (locale == null) return context.appLocalizations.defaultText;
    return locale.label;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(
      appSettingProvider.select((state) => state.locale),
    );
    final currentLocale = getLocaleForString(locale);
    return ListItem<Locale?>.options(
      leading: const GlyphIcon(AppGlyphs.language),
      title: Text(context.appLocalizations.language),
      options: [null, ...AppLocalizations.delegate.supportedLocales],
      onChanged: (Locale? locale) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(locale: locale?.toString()));
      },
      textBuilder: (locale) => _getLocaleString(context, locale),
      value: currentLocale,
    );
  }
}

class _ThemeItem extends StatelessWidget {
  const _ThemeItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.paintbrush),
      title: Text(context.appLocalizations.theme),
      widget: const ThemeView(),
    );
  }
}

class _BackupItem extends StatelessWidget {
  const _BackupItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.cloudSync),
      title: Text(context.appLocalizations.backupAndRestore),
      widget: const BackupAndRestore(),
    );
  }
}

class _HotkeyItem extends StatelessWidget {
  const _HotkeyItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.keyboard),
      title: Text(context.appLocalizations.hotkeyManagement),
      widget: const HotKeyView(),
    );
  }
}

class _AccessItem extends StatelessWidget {
  const _AccessItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.appsList),
      title: Text(context.appLocalizations.accessControl),
      widget: const AccessView(),
    );
  }
}

class _AdvancedGateItem extends StatelessWidget {
  const _AdvancedGateItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.wrench),
      title: Text(context.appLocalizations.advanced),
      widget: const AdvancedGateView(),
    );
  }
}

class _DisclaimerItem extends StatelessWidget {
  const _DisclaimerItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.gavel),
      title: Text(context.appLocalizations.disclaimer),
      widget: const DisclaimerView(),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.info),
      title: Text(context.appLocalizations.about),
      widget: const AboutView(),
    );
  }
}
