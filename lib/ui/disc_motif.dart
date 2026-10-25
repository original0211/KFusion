import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The brand mark as a flat decoration: the logo's disc with its crescent bite, at the master's proportions.
class DashboardDiscMotif extends StatelessWidget {
  const DashboardDiscMotif({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DiscMotifPainter(color),
    );
  }
}

class _DiscMotifPainter extends CustomPainter {
  const _DiscMotifPainter(this.color);

  final Color color;

  // The master's bite: centred just past the rim at 157 degrees, it cuts the disc back to 0.61 of its radius along that ray.
  static const _biteDirection = 157 * math.pi / 180;
  static const _biteDistance = 1.28;
  static const _biteRadius = 0.67;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final biteCenter =
        center + Offset.fromDirection(_biteDirection, radius * _biteDistance);
    final path = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      Path()..addOval(
        Rect.fromCircle(center: biteCenter, radius: radius * _biteRadius),
      ),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DiscMotifPainter oldDelegate) =>
      oldDelegate.color != color;
}
