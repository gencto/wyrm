import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// What the notice above an unlock form says (unlock-discover.md §2):
/// a title in the tone's ink and one or two lines.
final class UnlockNoticeVm extends Equatable {
  const UnlockNoticeVm({
    required this.title,
    required this.text,
    this.tone = Tone.warn,
  });

  final String title;
  final String text;

  /// `warn` (amber: fallback, changed), `bad` (coral: signed out) or
  /// `neutral` (grey: no biometric here).
  final Tone tone;

  @override
  List<Object?> get props => [title, text, tone];
}

/// The notice of the boards `UnlockFallback`, `UnlockChanged`,
/// `UnlockSignedOut` and `UnlockLinux`: padding 14 × 16, radius 10, gap 8,
/// the title 14 in the tone's ink, the text 13 `text3` at 1.5.
class UnlockNotice extends StatelessWidget {
  const UnlockNotice({required this.vm, super.key});

  final UnlockNoticeVm vm;

  /// The boards' amber notice (`#6A5A2A` on `#1A1810`) and the coral one's
  /// fill (`#1C1513`).

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (border, fill, ink) = switch (vm.tone) {
      .warn => (c.noticeLine, c.noticeFill, c.warn),
      .bad => (c.badLine, c.refusalFill, c.badText),
      _ => (c.line2, c.ground1, c.text2),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: Insets.notice,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            Text(
              vm.title,
              style: TextStyle(fontSize: FontSizes.lg, color: ink),
            ),
            Text(
              vm.text,
              style: TextStyle(
                fontSize: FontSizes.md,
                height: 1.5,
                color: c.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
