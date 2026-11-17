import 'package:flutter_test/flutter_test.dart';
import 'package:ui/generated/assets.gen.dart';
import 'package:ui/indicators/app_icon.dart';

/// [AppIcon] is the one list of icons: every drawing of the canvas set has
/// its case, and every case of the set has its drawing.
void main() {
  test('the enum and `assets/svg/icons` name the same icons', () {
    final files = [
      for (final i in Assets.svg.icons.values)
        i.path.split('/').last.replaceAll('.svg', ''),
    ];
    expect([for (final i in AppIcon.canvas) i.asset], files);
  });

  test('an icon has one source: a drawing of the set or a glyph', () {
    for (final i in AppIcon.values) {
      expect((i.asset == null) != (i.glyph == null), isTrue, reason: i.name);
    }
  });
}
