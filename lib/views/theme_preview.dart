import 'dart:math' as math;

import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/providers/state.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PreviewChoice<T> {
  const PreviewChoice({
    required this.value,
    required this.label,
    this.pictogram,
  });

  final T value;
  final String label;
  final Widget? pictogram;
}

class PreviewChoiceGroup<T> extends StatelessWidget {
  const PreviewChoiceGroup({
    super.key,
    required this.info,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.actions = const [],
  });

  final Info info;
  final List<PreviewChoice<T>> choices;
  final T value;
  final ValueChanged<T> onChanged;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                info.label,
                style: HaraText.sectionTitle(context, palette.sub),
              ),
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: HaraSpace.sectionTitleGap),
        HaraHairline(color: palette.line),
        for (final choice in choices)
          _PreviewChoiceRow<T>(
            choice: choice,
            selected: choice.value == value,
            onPressed: () => onChanged(choice.value),
          ),
      ],
    );
  }
}

class _PreviewChoiceRow<T> extends StatelessWidget {
  const _PreviewChoiceRow({
    required this.choice,
    required this.selected,
    required this.onPressed,
  });

  final PreviewChoice<T> choice;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return InkWell(
      customBorder: AppShape.hara,
      onTap: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: HaraSpace.nodeRowVertical,
            ),
            child: Row(
              children: [
                if (choice.pictogram != null) ...[
                  ExcludeSemantics(child: choice.pictogram!),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Text(
                    choice.label,
                    style: HaraText.nodeName(
                      context,
                      palette.ink,
                      current: selected,
                    ),
                  ),
                ),
                if (selected) SelectionCheck(color: palette.ink),
              ],
            ),
          ),
          HaraHairline(color: palette.line),
        ],
      ),
    );
  }
}

/// The foot of a [MiniScreen], where the options differ, drawn at the size of
/// an icon.
class MiniScreenThumb extends StatelessWidget {
  const MiniScreenThumb({super.key, required this.screen});

  static const Size _screenSize = Size(96, 128);
  static const double _shownHeight = 66;
  static const double _height = 30;

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return SizedBox(
      height: _height,
      width: _height * _screenSize.width / _shownHeight,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: AppShape.hara.copyWith(
            side: BorderSide(color: palette.line, width: HaraSpace.hairline),
          ),
        ),
        child: ClipRSuperellipse(
          borderRadius: AppRadius.hara,
          child: FittedBox(
            child: SizedBox(
              width: _screenSize.width,
              height: _shownHeight,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: _screenSize.height,
                  maxHeight: _screenSize.height,
                  child: screen,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSchemeTween extends Tween<ColorScheme> {
  _ColorSchemeTween({super.end});

  @override
  ColorScheme lerp(double t) => ColorScheme.lerp(begin!, end!, t);
}

/// The home page as the theme settings will draw it; its destinations can be
/// tapped to try the tab animation.
class ThemeLivePreview extends ConsumerStatefulWidget {
  const ThemeLivePreview({super.key});

  @override
  ConsumerState<ThemeLivePreview> createState() => _ThemeLivePreviewState();
}

class _ThemeLivePreviewState extends ConsumerState<ThemeLivePreview>
    with SingleTickerProviderStateMixin {
  static const double _phoneWidth = 168;
  static const _duration = Duration(milliseconds: 300);

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: kTabScrollDuration,
  );
  late final CurvedAnimation _slideCurve = CurvedAnimation(
    parent: _slide,
    curve: Curves.easeOut,
  );
  int _selected = 0;
  int? _previous;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      appSettingProvider.select((state) => state.tabAnimation),
      (_, _) => _select((_selected + 1) % MiniScreen.destinationCount),
    );
  }

  Future<void> _select(int index) async {
    if (index == _selected) {
      return;
    }
    final tabAnimation = ref.read(appSettingProvider).tabAnimation;
    final fade = tabAnimation == TabAnimation.fade;
    _slide.duration = fade ? fadeTabDuration : kTabScrollDuration;
    _slideCurve.curve = fade ? fadeTabCurve : Curves.easeOut;
    setState(() {
      _previous = _selected;
      _selected = index;
    });
    await _slide.forward(from: 0).orCancel.catchError((_) {});
    if (mounted && _selected == index) {
      setState(() => _previous = null);
    }
  }

  @override
  void dispose() {
    _slideCurve.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightScheme = ref.watch(genColorSchemeProvider(Brightness.light));
    final darkScheme = ref.watch(genColorSchemeProvider(Brightness.dark));
    final floatingBar = ref.watch(
      appSettingProvider.select((state) => state.floatingNavigationBar),
    );
    final tabAnimation = ref.watch(
      appSettingProvider.select((state) => state.tabAnimation),
    );
    final liquidGlass = ref.watch(
      themeSettingProvider.select(
        (state) => state.liquidGlass != LiquidGlassMode.none,
      ),
    );
    final palette = context.haraPalette;
    Widget phone(ColorScheme scheme, double width) => SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 9 / 17,
        child: CustomPaint(
          foregroundPainter: _PreviewFramePainter(palette.line),
          child: ClipRSuperellipse(
            borderRadius: AppRadius.hara,
            child: TweenAnimationBuilder<ColorScheme>(
              tween: _ColorSchemeTween(end: scheme),
              duration: _duration,
              builder: (_, colorScheme, _) => AnimatedBuilder(
                animation: _slideCurve,
                builder: (_, _) => MiniScreen(
                  key: ValueKey((floatingBar, liquidGlass)),
                  colorScheme: colorScheme,
                  floatingBar: floatingBar,
                  liquidGlass: liquidGlass,
                  selected: _selected,
                  previous: _previous,
                  progress: _previous == null ? 1 : _slideCurve.value,
                  tabAnimation: tabAnimation,
                  onSelect: _select,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final width = math.min(_phoneWidth, (constraints.maxWidth - 12) / 2);
          return Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [phone(lightScheme, width), phone(darkScheme, width)],
          );
        },
      ),
    );
  }
}

enum _MiniPage { dashboard, proxies, profiles, tools }

/// The hairline frame of a live preview phone, painted over the sketch so
/// the phones read as framed schematics on the page field.
class _PreviewFramePainter extends CustomPainter {
  const _PreviewFramePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      (Offset.zero & size).deflate(HaraSpace.hairline / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = HaraSpace.hairline
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PreviewFramePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A phone-shaped sketch of the home page, drawn in [colorScheme].
///
/// With [previous], the page is caught [progress] of the way through a switch
/// from it, drawn as [tabAnimation] moves the pages.
class MiniScreen extends StatelessWidget {
  const MiniScreen({
    super.key,
    required this.colorScheme,
    required this.floatingBar,
    this.liquidGlass = false,
    this.selected = 0,
    this.previous,
    this.progress = 1,
    this.tabAnimation = TabAnimation.slide,
    this.onSelect,
  });

  static const int destinationCount = 4;

  final ColorScheme colorScheme;
  final bool floatingBar;

  /// Draws a floating bar with a second inner frame, the schematic's way of
  /// showing the glass tier; a docked one stays a strip on the page foot.
  final bool liquidGlass;

  final int selected;
  final int? previous;
  final double progress;
  final TabAnimation tabAnimation;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final sketch = SizedBox.expand(
      child: CustomPaint(
        painter: _MiniScreenPainter(
          colorScheme: colorScheme,
          floatingBar: floatingBar,
          liquidGlass: liquidGlass,
          selected: selected,
          previous: previous,
          progress: progress,
          tabAnimation: tabAnimation,
        ),
      ),
    );
    final onSelect = this.onSelect;
    if (onSelect == null) {
      return sketch;
    }
    return LayoutBuilder(
      builder: (_, constraints) {
        final geometry = _MiniGeometry(
          constraints.biggest,
          floatingBar: floatingBar,
        );
        return Stack(
          children: [
            sketch,
            Positioned.fromRect(
              rect: geometry.bar,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < destinationCount; i++)
                    Expanded(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class MiniSplitScreen extends StatelessWidget {
  const MiniSplitScreen({super.key, required this.light, required this.dark});

  final Widget light;
  final Widget dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        light,
        ClipPath(clipper: _DiagonalClipper(), child: dark),
      ],
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.3, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_DiagonalClipper oldClipper) => false;
}

class _MiniGeometry {
  _MiniGeometry(this.size, {required bool floatingBar})
    : unit = size.width / 20 {
    margin = unit * 1.5;
    final barHeight = floatingBar ? unit * 3.2 : unit * 3.6;
    pageBottom = floatingBar ? 0 : barHeight;
    bar = floatingBar
        ? Rect.fromLTWH(
            margin,
            size.height - margin - barHeight,
            size.width - margin * 2,
            barHeight,
          )
        : Rect.fromLTWH(0, size.height - barHeight, size.width, barHeight);
  }

  final Size size;
  final double unit;
  late final double margin;
  late final double pageBottom;
  late final Rect bar;
}

class _MiniScreenPainter extends CustomPainter {
  const _MiniScreenPainter({
    required this.colorScheme,
    required this.floatingBar,
    required this.liquidGlass,
    required this.selected,
    required this.previous,
    required this.progress,
    required this.tabAnimation,
  });

  final ColorScheme colorScheme;
  final bool floatingBar;
  final bool liquidGlass;
  final int selected;
  final int? previous;
  final double progress;
  final TabAnimation tabAnimation;

  bool get _glass => floatingBar && liquidGlass;

  bool get _dark => colorScheme.brightness == Brightness.dark;

  /// The bar's wash: a step of the ground's own ink, never a tinted fill.
  Color get _wash =>
      colorScheme.onSurface.withValues(alpha: _dark ? 0.10 : 0.06);

  Color get _frame => colorScheme.onSurface.withValues(alpha: 0.45);

  static _MiniPage _pageOf(int index) =>
      _MiniPage.values[index % _MiniPage.values.length];

  static void _fill(Canvas canvas, Rect rect, Color color, ShapeBorder shape) {
    ShapeDecoration(color: color, shape: shape)
        .createBoxPainter(() {})
        .paint(canvas, rect.topLeft, ImageConfiguration(size: rect.size));
  }

  static void _strokeRect(Canvas canvas, Rect rect, Color color, double unit) {
    canvas.drawRect(
      rect.deflate(unit * 0.065),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.13
        ..color = color,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _MiniGeometry(size, floatingBar: floatingBar);
    _paintPages(canvas, geometry);
    final unit = geometry.unit;
    final bar = geometry.bar;
    _fill(canvas, bar, _wash, AppShape.hara);
    if (floatingBar) {
      _strokeRect(canvas, bar, _frame, unit);
      if (_glass) {
        _strokeRect(canvas, bar.deflate(unit * 0.45), _frame, unit);
      }
    } else {
      canvas.drawRect(
        Rect.fromLTWH(bar.left, bar.top, bar.width, unit * 0.13),
        Paint()..color = _frame,
      );
    }
    _paintDestinations(canvas, geometry.bar, unit);
  }

  void _paintPages(Canvas canvas, _MiniGeometry geometry) {
    final size = geometry.size;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = SurfaceLevel.page.colorOf(colorScheme),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size, doAntiAlias: false);
    final previous = this.previous;
    if (previous == null) {
      _paintPage(canvas, geometry, selected, 0);
    } else if (tabAnimation == TabAnimation.fade) {
      _paintPage(canvas, geometry, previous, 0, opacity: 1 - progress);
      _paintPage(canvas, geometry, selected, 0, opacity: progress);
    } else {
      final direction = previous > selected ? -1 : 1;
      _paintPage(
        canvas,
        geometry,
        previous,
        -direction * size.width * progress,
      );
      _paintPage(
        canvas,
        geometry,
        selected,
        direction * size.width * (1 - progress),
      );
    }
    canvas.restore();
  }

  void _paintPage(
    Canvas canvas,
    _MiniGeometry geometry,
    int index,
    double offset, {
    double opacity = 1,
  }) {
    final alpha = Color.getAlphaFromOpacity(opacity);
    if (alpha == 0) {
      return;
    }
    final size = geometry.size;
    final margin = geometry.margin;
    final content = Rect.fromLTRB(
      offset + margin,
      margin,
      offset + size.width - margin,
      size.height - geometry.pageBottom,
    );
    if (alpha < 255) {
      canvas.saveLayer(
        null,
        Paint()..color = colorScheme.shadow.withAlpha(alpha),
      );
    } else {
      canvas.save();
    }
    canvas.clipRect(content, doAntiAlias: false);
    _PageSketch(
      canvas,
      colorScheme,
      geometry.unit,
      content,
    ).paint(_pageOf(index));
    canvas.restore();
  }

  void _paintDestinations(Canvas canvas, Rect bar, double unit) {
    final cell = bar.width / MiniScreen.destinationCount;
    final dark = colorScheme.brightness == Brightness.dark;
    final indicator = colorScheme.onSurface.withValues(
      alpha: dark ? 0.16 : 0.10,
    );
    for (var i = 0; i < MiniScreen.destinationCount; i++) {
      final center = Offset(bar.left + cell * i + cell / 2, bar.center.dy);
      final icon = center.translate(0, -unit * 0.4);
      final isSelected = i == selected;
      if (isSelected) {
        _fill(
          canvas,
          floatingBar
              ? Rect.fromCenter(
                  center: center,
                  width: cell - unit * 0.5,
                  height: bar.height - unit * 0.5,
                )
              : Rect.fromCenter(
                  center: icon,
                  width: unit * 2.8,
                  height: unit * 1.5,
                ),
          indicator,
          AppShape.hara,
        );
      }
      final ink = isSelected
          ? colorScheme.onSurface
          : colorScheme.onSurfaceVariant;
      _fill(
        canvas,
        Rect.fromCircle(center: icon, radius: unit * 0.45),
        ink,
        AppShape.circle,
      );
      _fill(
        canvas,
        Rect.fromCenter(
          center: center.translate(0, unit * 0.8),
          width: unit * 1.7,
          height: unit * 0.35,
        ),
        isSelected ? ink : ink.withValues(alpha: 0.6),
        AppShape.hara,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniScreenPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.floatingBar != floatingBar ||
        oldDelegate.liquidGlass != liquidGlass ||
        oldDelegate.selected != selected ||
        oldDelegate.previous != previous ||
        oldDelegate.progress != progress ||
        oldDelegate.tabAnimation != tabAnimation;
  }
}

/// One page of a [MiniScreen] after the app's own, laid out in units of a
/// twentieth of the screen's width from the top left of [content].
class _PageSketch {
  _PageSketch(this.canvas, this.colorScheme, this.unit, this.content)
    : width = content.width / unit,
      ground = SurfaceLevel.page.colorOf(colorScheme),
      wash = colorScheme.onSurface.withValues(
        alpha: colorScheme.brightness == Brightness.dark ? 0.09 : 0.05,
      ),
      text = colorScheme.onSurface.withValues(alpha: 0.72),
      line = colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      faint = colorScheme.onSurfaceVariant.withValues(alpha: 0.16);

  static const double _gap = 0.6;

  final Canvas canvas;
  final ColorScheme colorScheme;
  final double unit;
  final Rect content;
  final double width;
  final Color ground;
  final Color wash;
  final Color text;
  final Color line;
  final Color faint;

  void paint(_MiniPage page) {
    switch (page) {
      case _MiniPage.dashboard:
        _dashboard(_header(actions: 1));
      case _MiniPage.proxies:
        _proxies(_header(actions: 2));
      case _MiniPage.profiles:
        _profiles(_header(actions: 2));
      case _MiniPage.tools:
        _tools(_header(actions: 0));
    }
  }

  Rect _rect(double x, double y, double w, double h) => Rect.fromLTWH(
    content.left + x * unit,
    content.top + y * unit,
    w * unit,
    h * unit,
  );

  /// A block of the sketch: a wash of the ground's ink inside a hairline
  /// frame, where the drawn app would set a card.
  void _block(Rect rect) {
    _MiniScreenPainter._fill(canvas, rect, wash, AppShape.hara);
    _MiniScreenPainter._strokeRect(canvas, rect, line, unit);
  }

  void _pill(double x, double y, double w, double h, Color color) {
    _MiniScreenPainter._fill(canvas, _rect(x, y, w, h), color, AppShape.hara);
  }

  void _dot(double x, double y, double radius, Color color) {
    _MiniScreenPainter._fill(
      canvas,
      _rect(x - radius, y - radius, radius * 2, radius * 2),
      color,
      AppShape.circle,
    );
  }

  /// The title and the bar's round buttons; returns where the body starts.
  double _header({required int actions}) {
    _pill(0, 0.45, 7, 1.1, text);
    for (var i = 0; i < actions; i++) {
      final x = width - 1 - i * 2.4;
      _dot(x, 1, 1, wash);
      _dot(x, 1, 0.3, line);
    }
    return 2.8;
  }

  void _dashboard(double top) {
    var y = top;
    final status = _rect(0, y, width, 6.2);
    final buttonX = width - 3;
    final buttonY = y + 3.1;
    _block(status);
    _dot(buttonX, buttonY, 1.8, colorScheme.primary);
    for (final dx in [-0.675, 0.325]) {
      _pill(buttonX + dx, buttonY - 0.6, 0.35, 1.2, colorScheme.onPrimary);
    }
    _pill(1, y + 0.9, 3, 0.7, line);
    _dot(1.9, y + 3, 0.9, faint);
    _pill(3.5, y + 2.3, 5, 0.9, text);
    _pill(3.5, y + 3.5, 2.4, 0.7, faint);
    _pill(1, y + 4.8, 2.4, 0.7, line);
    _pill(4.6, y + 4.8, 3.6, 0.7, line);
    y += 6.2 + _gap;

    _block(_rect(0, y, width, 5.8));
    _pill(1, y + 0.9, 4.5, 0.7, line);
    final tileWidth = (width - 2.6) / 2;
    for (var i = 0; i < 2; i++) {
      final x = 1 + i * (tileWidth + 0.6);
      final tile = _rect(x, y + 2.1, tileWidth, 2.9);
      _block(tile);
      _pill(x + 0.6, y + 2.65, 2.4, 0.7, line);
      _speedGraph(tile, phase: i * 1.7, color: i == 0 ? line : text);
    }
    y += 5.8 + _gap;

    _block(_rect(0, y, width, 4.4));
    _pill(1, y + 0.9, 4, 0.7, line);
    final segment = (width - 2.6) / 3;
    for (var i = 0; i < 3; i++) {
      final x = 1 + i * (segment + 0.3);
      _pill(x, y + 2.1, segment, 1.6, i == 0 ? text : wash);
      _dot(x + segment / 2, y + 2.9, 0.3, i == 0 ? ground : line);
    }
    y += 4.4 + _gap;

    _block(_rect(0, y, width, 3));
    _dot(1.9, y + 1.5, 0.9, text);
    _pill(3.4, y + 1.1, 2.4, 0.8, line);
    _pill(width - 3.6, y + 0.8, 2.6, 1.4, text);
    _dot(width - 1.7, y + 1.5, 0.55, ground);
    y += 3 + _gap;

    for (var i = 0; i < 3; i++) {
      _block(_rect(0, y, width, 4.5));
      _pill(1, y + 0.9, 3.5 + i % 2, 0.7, line);
      y += 4.5 + _gap;
    }
  }

  void _speedGraph(Rect tile, {required double phase, required Color color}) {
    const steps = 16;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final x = tile.left + tile.width * i / steps;
      final y =
          tile.top +
          tile.height * 0.68 +
          math.sin(i * 0.9 + phase) * unit * 0.35;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final area = Path.from(path)
      ..lineTo(tile.right, tile.bottom)
      ..lineTo(tile.left, tile.bottom)
      ..close();
    canvas
      ..save()
      ..clipRect(tile)
      ..drawPath(area, Paint()..color = color.withValues(alpha: color.a * 0.2))
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.15
          ..color = color,
      )
      ..restore();
  }

  void _proxies(double top) {
    var y = top;
    for (var i = 0; i < 9; i++) {
      _block(_rect(0, y, width, 2.6));
      _dot(1.5, y + 1.3, 0.8, faint);
      _pill(3, y + 0.6, 3 + i % 3, 0.7, line);
      _pill(3, y + 1.55, 4, 0.5, faint);
      _pill(width - 4.4, y + 1.05, 1.8, 0.5, faint);
      _dot(width - 1.3, y + 1.3, 0.55, faint);
      y += 2.6 + _gap;
    }
  }

  void _profiles(double top) {
    var y = top;
    for (var i = 0; i < 3; i++) {
      _block(_rect(0, y, width, 2.8));
      _pill(1, y + 0.7, 3.4 - i * 0.6, 0.75, line);
      _pill(4.8 - i * 0.6, y + 0.72, 2.6, 0.7, faint);
      _pill(1, y + 1.7, 3, 0.5, faint);
      _pill(width - 4.1, y + 1.15, 1.6, 0.5, faint);
      if (i == 0) {
        _dot(width - 1.4, y + 1.4, 0.6, text);
      }
      y += 2.8 + _gap;
    }
  }

  void _tools(double top) {
    const rowHeight = 2.4;
    var y = top;
    for (final rows in [4, 7]) {
      _pill(0.8, y + 0.2, 1.6 + rows * 0.15, 0.5, faint);
      y += 1.3;
      _block(_rect(0, y, width, rows * rowHeight));
      for (var i = 0; i < rows; i++) {
        final row = y + i * rowHeight;
        _dot(1.3, row + rowHeight / 2, 0.45, line);
        _pill(2.6, row + 0.85, 4 + (i * 3 + rows) % 4, 0.7, line);
        if (i < rows - 1) {
          canvas.drawRect(
            _rect(2.6, row + rowHeight - 0.03, width - 3.4, 0.06),
            Paint()..color = faint,
          );
        }
      }
      y += rows * rowHeight + _gap * 2;
    }
  }
}
