import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/providers/action.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeveloperView extends ConsumerWidget {
  const DeveloperView({super.key});

  List<Widget> _getDeveloperRows(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    return [
      HaraRow(
        onTap: () async {
          final storeAction = ref.read(storeActionProvider.notifier);
          final res = await dialogs.showMessage(
            message: TextSpan(text: appLocalizations.confirmClearAllData),
            destructive: true,
            confirmText: appLocalizations.clearData,
          );
          if (res != true) {
            return;
          }
          await storeAction.handleClear();
        },
        child: Text(
          appLocalizations.clearData,
          style: HaraText.nodeName(
            context,
            context.haraPalette.ink,
            current: false,
          ),
        ),
      ),
      HaraRow(
        onTap: () async {
          await ref.read(storeActionProvider.notifier).shakingStore();
        },
        child: Text(
          appLocalizations.pruneCache,
          style: HaraText.nodeName(
            context,
            context.haraPalette.ink,
            current: false,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final enable = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    return BaseScaffold(
      title: appLocalizations.developerMode,
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
                _HaraToggleRow(
                  label: appLocalizations.developerMode,
                  value: enable,
                  onTap: () {
                    ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) => state.copyWith(developerMode: !enable),
                        );
                  },
                ),
                const SizedBox(height: HaraSpace.groupGap),
                HaraSection(
                  title: appLocalizations.options,
                  rows: _getDeveloperRows(context, ref),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A toggle row: the row tap flips the value, the state reads as the
/// shared toggle mark at the row's end.
class _HaraToggleRow extends StatelessWidget {
  const _HaraToggleRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    return Semantics(
      toggled: value,
      child: HaraRow(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: HaraText.nodeName(context, palette.ink, current: false),
              ),
            ),
            HaraToggleMark(
              value: value,
              word: value
                  ? appLocalizations.enabled
                  : appLocalizations.disabled,
            ),
          ],
        ),
      ),
    );
  }
}
