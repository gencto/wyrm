import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// What unlocks the key, as the boards draw it (`Unlock`, `UnlockPlatforms`):
/// a fingerprint (Touch ID, Android fingerprint), a face (Face ID, Windows
/// Hello, Android face) or a key (no biometric here).
enum BiometricGlyph { finger, face, key }

/// The boards' line icon of [glyph], [size] square, in [color], with the
/// stroke of the 24-unit box ([stroke]). [compact] drops the outer strands
/// of the fingerprint, as the boards' prompts and step-up do.
class BiometricIcon extends StatelessWidget {
  const BiometricIcon({
    required this.glyph,
    this.size = 44,
    this.color,
    this.stroke = 1.6,
    this.compact = false,
    super.key,
  });

  final BiometricGlyph glyph;
  final double size;
  final Color? color;
  final double stroke;
  final bool compact;

  static const _finger = [
    'M2 12C2 6.5 6.5 2 12 2a10 10 0 0 1 8 4',
    'M5 19.5C5.5 18 6 15 6 12c0-.7.12-1.37.34-2',
    'M17.29 21.02c.12-.6.43-2.3.5-3.02',
    'M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4',
    'M8.65 22c.21-.66.45-1.32.57-2',
    'M14 13.12c0 2.38 0 6.38-1 8.88',
    'M2 16h.01',
    'M21.8 16c.2-2 .131-5.354 0-6',
    'M9 6.8a6 6 0 0 1 9 5.2c0 .47 0 1.17-.02 2',
  ];

  static const _fingerCompact = [
    'M2 12C2 6.5 6.5 2 12 2a10 10 0 0 1 8 4',
    'M5 19.5C5.5 18 6 15 6 12c0-.7.12-1.37.34-2',
    'M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4',
    'M14 13.12c0 2.38 0 6.38-1 8.88',
    'M9 6.8a6 6 0 0 1 9 5.2c0 .47 0 1.17-.02 2',
  ];

  static const _face = [
    'M3 7V5a2 2 0 0 1 2-2h2',
    'M17 3h2a2 2 0 0 1 2 2v2',
    'M21 17v2a2 2 0 0 1-2 2h-2',
    'M7 21H5a2 2 0 0 1-2-2v-2',
    'M8 14s1.5 2 4 2 4-2 4-2',
    'M9 9h.01',
    'M15 9h.01',
  ];

  static const _key = ['M10.85 12.15 19 4M18 5l2 2M15 8l2 2'];

  String _svg(Color c) {
    final paths = switch (glyph) {
      .finger => compact ? _fingerCompact : _finger,
      .face => _face,
      .key => _key,
    };
    final hex =
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final circle = glyph == .key ? '<circle cx="8" cy="15" r="4"/>' : '';
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="$hex" stroke-opacity="${c.a}" '
        'stroke-width="$stroke" stroke-linecap="round" '
        'stroke-linejoin="round">$circle'
        '${[for (final d in paths) '<path d="$d"/>'].join()}</svg>';
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFFF3A766);
    return ExcludeSemantics(
      child: SvgPicture.string(_svg(c), width: size, height: size),
    );
  }
}
