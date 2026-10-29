import 'dart:ui';

import 'package:kfusion/ui/inherited.dart';
import 'package:material_ui/material_ui.dart';

Widget commonProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    builder: (_, Widget? child) {
      final double animValue = Curves.easeInOut.transform(animation.value);
      final double scale = lerpDouble(1, 1.02, animValue)!;
      return ProxyDecoratorProvider(
        isProxyDecorator: true,
        lift: animValue,
        child: Transform.scale(scale: scale, child: child),
      );
    },
    child: child,
  );
}
