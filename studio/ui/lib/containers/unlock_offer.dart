import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/log_in_button.dart';
import '../indicators/biometric_icon.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import 'rise.dart';

/// One fact of the offer: its words and the colour of its dot.
final class OfferFactVm extends Equatable {
  const OfferFactVm(this.text, {this.tone = Tone.good});

  final String text;

  /// `good` (teal), `warn` (amber) or `neutral` (grey).
  final Tone tone;

  @override
  List<Object?> get props => [text, tone];
}

/// What the offer after a password login says (board `UnlockOffer`,
/// unlock-discover.md §2), resolved.
final class UnlockOfferVm extends Equatable {
  const UnlockOfferVm({
    required this.checked,
    required this.glyph,
    required this.title,
    required this.text,
    required this.facts,
    required this.policy,
    this.use,
    this.notNow = '',
    this.dontAsk = '',
    this.open = '',
    this.busy = false,
  });

  /// `Logged in to <site> as <user> · <role>`.
  final String checked;
  final BiometricGlyph glyph;
  final String title;
  final String text;
  final List<OfferFactVm> facts;

  /// The gateway's policy line.
  final String policy;

  /// `Use <name>`; null on a computer with no biometric, which offers
  /// [open] alone.
  final String? use;
  final String notNow;
  final String dontAsk;
  final String open;

  /// The key is being made and registered.
  final bool busy;

  @override
  List<Object?> get props => [
    checked,
    glyph,
    title,
    text,
    facts,
    policy,
    use,
    notNow,
    dontAsk,
    open,
    busy,
  ];
}

/// The offer: the check line in teal, the platform tile 84 (radius 24,
/// `emberFill`, `emberLine`), the title 26/600, one line, the facts with
/// dots, `Use <name>` (ember, 50), `Not now` and `Don't ask on this
/// computer` (42, outlined), and the policy line (12 `text4`).
class UnlockOffer extends StatelessWidget {
  const UnlockOffer({
    required this.vm,
    required this.onUse,
    required this.onNotNow,
    required this.onDontAsk,
    super.key,
  });

  final UnlockOfferVm vm;

  /// `Use <name>`, or `Open Studio` without a biometric.
  final VoidCallback onUse;
  final VoidCallback onNotNow;
  final VoidCallback onDontAsk;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color dot(Tone t) => switch (t) {
      .good => c.good,
      .warn => c.warn,
      _ => c.muted,
    };
    return Rise(
      child: Column(
        crossAxisAlignment: .start,
        spacing: 18,
        children: [
          Row(
            spacing: 8,
            children: [
              CustomPaint(size: const Size.square(14), painter: _Check(c.good)),
              Flexible(
                child: Text(
                  vm.checked,
                  style: TextStyle(fontSize: 13, color: c.good),
                ),
              ),
            ],
          ),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: c.emberFill,
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              border: Border.all(color: c.emberLine),
            ),
            alignment: .center,
            child: BiometricIcon(
              glyph: vm.glyph,
              size: vm.glyph == .key ? 40 : 44,
              color: c.emberSoft,
            ),
          ),
          Column(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Text(
                vm.title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: .w600,
                  letterSpacing: -.26,
                  color: c.text1,
                ),
              ),
              Text(
                vm.text,
                style: TextStyle(fontSize: 14, height: 1.55, color: c.text3),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: .stretch,
            spacing: 8,
            children: [
              for (final f in vm.facts)
                Row(
                  crossAxisAlignment: .start,
                  spacing: 10,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dot(f.tone),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        f.text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: c.text2,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (vm.use case final use?)
            Column(
              crossAxisAlignment: .stretch,
              spacing: 10,
              children: [
                OfferButton(label: use, onPressed: onUse, busy: vm.busy),
                Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: _Outlined(
                        label: vm.notNow,
                        border: c.line3,
                        ink: c.text1,
                        onPressed: vm.busy ? null : onNotNow,
                      ),
                    ),
                    Expanded(
                      child: _Outlined(
                        label: vm.dontAsk,
                        border: c.line1,
                        ink: c.text3,
                        onPressed: vm.busy ? null : onDontAsk,
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: OfferButton(label: vm.open, onPressed: onUse),
            ),
          Text(
            vm.policy,
            style: TextStyle(fontSize: 12, height: 1.5, color: c.text4),
          ),
        ],
      ),
    );
  }
}

/// The ember button of the unlock forms (50 high, radius 10, 16/600), with
/// the log-in button's busy fill.
class OfferButton extends StatelessWidget {
  const OfferButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: busy ? LogInButton.busyFill : c.ember,
      clipBehavior: .antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: InkWell(
        onTap: busy ? null : onPressed,
        child: SizedBox(
          height: 50,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: .w600,
                color: c.onEmber,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Outlined extends StatelessWidget {
  const _Outlined({
    required this.label,
    required this.border,
    required this.ink,
    required this.onPressed,
  });

  final String label;
  final Color border;
  final Color ink;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      side: BorderSide(color: border),
    ),
    clipBehavior: .antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 42,
        child: Center(
          child: Text(label, style: TextStyle(fontSize: 14, color: ink)),
        ),
      ),
    ),
  );
}

/// The board's check: `M5 12l5 5 9-10`, stroke 2.6.
class _Check extends CustomPainter {
  _Check(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas
      ..save()
      ..scale(k)
      ..drawPath(
        Path()
          ..moveTo(5, 12)
          ..lineTo(10, 17)
          ..lineTo(19, 7),
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = 2.6
          ..strokeCap = .round
          ..strokeJoin = .round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_Check old) => old.color != color;
}
