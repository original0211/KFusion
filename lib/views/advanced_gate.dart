import 'package:kfusion/common/common.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/config/advanced.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/developer.dart';
import 'package:kfusion/views/font_family.dart';
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
    final appLocalizations = context.appLocalizations;
    final developerMode = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    final items = [
      ListItem.open(
        leading: const GlyphIcon(AppGlyphs.wrench),
        title: Text(appLocalizations.advancedConfig),
        widget: const AdvancedConfigView(),
      ),
      ListItem.open(
        leading: const GlyphIcon(AppGlyphs.settings),
        title: Text(appLocalizations.general),
        widget: const GeneralView(),
      ),
      ListItem.open(
        leading: const GlyphIcon(AppGlyphs.sliders),
        title: Text(appLocalizations.proxySettings),
        widget: BaseScaffold(
          title: appLocalizations.proxySettings,
          body: const ProxiesSetting(),
        ),
      ),
      ListItem.open(
        leading: const GlyphIcon(AppGlyphs.resources),
        title: Text(appLocalizations.resources),
        widget: const ResourcesView(),
      ),
      ListItem.open(
        leading: const GlyphIcon(AppGlyphs.logs),
        title: Text(appLocalizations.logs),
        widget: const LogsView(),
      ),
      ListItem.open(
        leading: const GlyphIcon(AppGlyphs.font),
        title: Text(appLocalizations.fontFamily),
        widget: const FontFamilyView(),
      ),
      if (developerMode)
        ListItem.open(
          leading: const GlyphIcon(AppGlyphs.cpu),
          title: Text(appLocalizations.developerMode),
          widget: const DeveloperView(),
        ),
    ];
    return BaseScaffold(
      title: appLocalizations.advanced,
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ).copyWith(top: context.contentTopPadding, bottom: 16),
        children: [
          generateSection(
            items: items,
            footer: [
              appLocalizations.advancedConfigDesc,
              appLocalizations.customProfileResourcesDesc,
            ].join('\n'),
          ),
        ],
      ),
    );
  }
}
