import 'package:material_ui/material_ui.dart';

import 'hara.dart';
import 'shape.dart';

/// One text navigation entry. Labels only: the A navigation carries no
/// glyphs, badges or fills.
class HaraNavItem {
  const HaraNavItem({required this.label});

  final String label;
}

/// The phone's text navigation bar: one hairline over text entries, the
/// current entry in ink with a short ink rule under its label.
class HaraNavBar extends StatelessWidget {
  const HaraNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<HaraNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Material(
      color: palette.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HaraHairline(),
          SizedBox(
            height:
                HaraSpace.navHeight -
                HaraSpace.navTopPadding -
                HaraSpace.hairline,
            child: Padding(
              padding: const EdgeInsets.only(top: HaraSpace.navTopPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, item) in items.indexed)
                    Expanded(
                      child: _HaraNavBarButton(
                        label: item.label,
                        current: index == selectedIndex,
                        onTap: () => onSelected(index),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The desktop text rail: the brand row over text entries, the current
/// entry marked by a short ink rule at its left, one hairline at the right.
class HaraNavRail extends StatelessWidget {
  const HaraNavRail({
    super.key,
    required this.brand,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.topInset = 0,
    this.footer,
    this.backgroundColor,
  });

  final String brand;
  final List<HaraNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double topInset;
  final String? footer;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Container(
      width: HaraSpace.railWidth,
      decoration: BoxDecoration(
        color: backgroundColor ?? palette.bg,
        border: Border(
          right: BorderSide(color: palette.line, width: HaraSpace.hairline),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topInset),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: HaraSpace.pageInset,
                top: 20,
              ),
              child: Text(brand, style: HaraText.brand(context, palette.dim)),
            ),
            const SizedBox(height: 34),
            for (final (index, item) in items.indexed)
              _HaraNavRailButton(
                label: item.label,
                current: index == selectedIndex,
                onTap: () => onSelected(index),
              ),
            const Spacer(),
            if (footer != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: HaraSpace.pageInset,
                  bottom: 20,
                ),
                child: Text(
                  footer!,
                  style: HaraText.dataKey(context, palette.dim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HaraNavBarButton extends StatefulWidget {
  const _HaraNavBarButton({
    required this.label,
    required this.current,
    required this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_HaraNavBarButton> createState() => _HaraNavBarButtonState();
}

class _HaraNavBarButtonState extends State<_HaraNavBarButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Semantics(
      selected: widget.current,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (focused) => setState(() => _focused = focused),
        customBorder: AppShape.hara,
        splashColor: HaraPalette.transparent,
        highlightColor: HaraPalette.transparent,
        hoverColor: HaraPalette.transparent,
        focusColor: HaraPalette.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: _focused
                ? Border.all(color: palette.ink, width: 1)
                : const Border.fromBorderSide(BorderSide.none),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HaraText.navLabel(
                  context,
                  widget.current ? palette.ink : palette.dim,
                  current: widget.current,
                ),
              ),
              const SizedBox(height: HaraSpace.navUnderlineGap),
              Container(
                width: HaraSpace.navUnderlineWidth,
                height: HaraSpace.navUnderlineHeight,
                color: widget.current ? palette.ink : HaraPalette.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HaraNavRailButton extends StatefulWidget {
  const _HaraNavRailButton({
    required this.label,
    required this.current,
    required this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_HaraNavRailButton> createState() => _HaraNavRailButtonState();
}

class _HaraNavRailButtonState extends State<_HaraNavRailButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Semantics(
      selected: widget.current,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (focused) => setState(() => _focused = focused),
        customBorder: AppShape.hara,
        splashColor: HaraPalette.transparent,
        highlightColor: HaraPalette.transparent,
        hoverColor: HaraPalette.transparent,
        focusColor: HaraPalette.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: _focused
                ? Border.all(color: palette.ink, width: 1)
                : const Border.fromBorderSide(BorderSide.none),
          ),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: HaraSpace.pageInset),
                Container(
                  width: HaraSpace.navUnderlineWidth,
                  height: HaraSpace.navUnderlineHeight,
                  color: widget.current ? palette.ink : HaraPalette.transparent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HaraText.navLabel(
                      context,
                      widget.current ? palette.ink : palette.dim,
                      current: widget.current,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
