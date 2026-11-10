import 'dart:typed_data';
import 'dart:ui';

import 'try_on_filter.dart';

/// Shared by preview and export so the outline and the final PNG match.
class GarmentTemplate {
  const GarmentTemplate(this.category);
  final TryOnFilterCategory category;

  Size get outputSize => switch (category) {
    TryOnFilterCategory.top => const Size(720, 800),
    TryOnFilterCategory.jacket => const Size(760, 850),
    TryOnFilterCategory.pants => const Size(600, 900),
    TryOnFilterCategory.skirt => const Size(800, 720),
    TryOnFilterCategory.dress => const Size(600, 900),
    TryOnFilterCategory.shoes => const Size(900, 500),
  };

  Path path(Size size) {
    final p = Path();
    switch (category) {
      case TryOnFilterCategory.top:
        p.moveTo(.40, .02);
        p.quadraticBezierTo(.50, .17, .60, .02);
        p.lineTo(.76, .10);
        p.lineTo(1, .29);
        p.lineTo(.88, .45);
        p.lineTo(.76, .35);
        p.lineTo(.78, .98);
        p.quadraticBezierTo(.5, 1, .22, .98);
        p.lineTo(.24, .35);
        p.lineTo(.12, .45);
        p.lineTo(0, .29);
        p.lineTo(.24, .10);
        p.close();
      case TryOnFilterCategory.jacket:
        p.moveTo(.39, .02);
        p.lineTo(.5, .14);
        p.lineTo(.61, .02);
        p.lineTo(.78, .10);
        p.lineTo(1, .81);
        p.lineTo(.85, .87);
        p.lineTo(.72, .39);
        p.lineTo(.76, .98);
        p.quadraticBezierTo(.5, 1, .24, .98);
        p.lineTo(.28, .39);
        p.lineTo(.15, .87);
        p.lineTo(0, .81);
        p.lineTo(.22, .10);
        p.close();
      case TryOnFilterCategory.pants:
        p.moveTo(.12, .02);
        p.quadraticBezierTo(.5, .05, .88, .02);
        p.lineTo(.97, .98);
        p.lineTo(.59, 1);
        p.lineTo(.50, .40);
        p.lineTo(.41, 1);
        p.lineTo(.03, .98);
        p.close();
      case TryOnFilterCategory.skirt:
        p.moveTo(.25, .02);
        p.lineTo(.75, .02);
        p.quadraticBezierTo(.84, .45, 1, .94);
        p.quadraticBezierTo(.5, 1.04, 0, .94);
        p.quadraticBezierTo(.16, .45, .25, .02);
        p.close();
      case TryOnFilterCategory.dress:
        p.moveTo(.39, .02);
        p.quadraticBezierTo(.5, .12, .61, .02);
        p.lineTo(.68, .08);
        p.lineTo(.75, .25);
        p.lineTo(.64, .29);
        p.lineTo(.64, .43);
        p.quadraticBezierTo(.80, .72, 1, .96);
        p.quadraticBezierTo(.5, 1.04, 0, .96);
        p.quadraticBezierTo(.20, .72, .36, .43);
        p.lineTo(.36, .29);
        p.lineTo(.25, .25);
        p.lineTo(.32, .08);
        p.close();
      case TryOnFilterCategory.shoes:
        p.moveTo(.03, .13);
        p.lineTo(.19, .13);
        p.quadraticBezierTo(.20, .55, .40, .59);
        p.quadraticBezierTo(.48, .62, .47, .90);
        p.lineTo(.02, .90);
        p.close();
        p.moveTo(.97, .13);
        p.lineTo(.81, .13);
        p.quadraticBezierTo(.80, .55, .60, .59);
        p.quadraticBezierTo(.52, .62, .53, .90);
        p.lineTo(.98, .90);
        p.close();
    }
    return p.transform(
      Float64List.fromList([
        size.width,
        0,
        0,
        0,
        0,
        size.height,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ]),
    );
  }
}
