import 'package:kfusion/common/common.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/dns.dart';
import 'package:kfusion/views/config/network.dart';
import 'package:material_ui/material_ui.dart';

import 'rules.dart';

class AdvancedConfigView extends StatelessWidget {
  const AdvancedConfigView({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final items = [
      ListItem.open(
        title: Text(appLocalizations.network),
        leading: const GlyphIcon(AppGlyphs.key),
        widget: BaseScaffold(
          title: appLocalizations.network,
          body: const NetworkListView(),
        ),
      ),
      ListItem.open(
        title: const Text('DNS'),
        leading: const GlyphIcon(AppGlyphs.dns),
        widget: const DnsView(),
      ),
      ListItem.open(
        title: Text(appLocalizations.addedRules),
        leading: const GlyphIcon(AppGlyphs.rules),
        widget: const AddedRulesView(),
      ),
    ];
    return BaseScaffold(
      title: appLocalizations.advancedConfig,
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ).copyWith(top: context.contentTopPadding, bottom: 16),
        children: [generateSection(items: items)],
      ),
    );
  }
}
