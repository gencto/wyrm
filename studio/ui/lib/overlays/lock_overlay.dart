import 'dart:ui' show ImageFilter;

import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/unlock_button.dart';
import '../containers/rise.dart';
import '../containers/unlock_offer.dart' show OfferButton;
import '../containers/unlock_panel.dart' show LockGlyph;
import '../indicators/biometric_icon.dart';
import '../inputs/boxed_form_field.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';

/// What the card of a locked Studio says (board `UnlockLock`), resolved.
final class LockCardVm extends Equatable {
  const LockCardVm({
    required this.title,
    required this.text,
    required this.glyph,
    required this.unlockLabel,
    required this.usePassword,
    required this.logOut,
    required this.passwordLabel,
    required this.unlock,
    this.kept,
    this.error,
    this.checking = false,
    this.passwordOnly = false,
  });

  /// `Studio is locked`.
  final String title;

  /// `<user> on <site> · locked after <n> min without use. …`
  final String text;
  final BiometricGlyph glyph;

  /// `Unlock with <name>`.
  final String unlockLabel;

  /// `<n> changes are waiting in Review and apply; they are kept.`
  final String? kept;
  final String usePassword;
  final String logOut;
  final String passwordLabel;

  /// The button under the password: `Unlock`.
  final String unlock;
  final String? error;
  final bool checking;

  /// No key here (or it stopped working): the password at once.
  final bool passwordOnly;

  @override
  List<Object?> get props => [
    title,
    text,
    glyph,
    unlockLabel,
    kept,
    usePassword,
    logOut,
    passwordLabel,
    unlock,
    error,
    checking,
    passwordOnly,
  ];
}

/// The idle lock over the Studio shell (ADR 0050 §1.4, board `UnlockLock`):
/// while [card] is set, [child] stays mounted (its subscriptions and *Review
/// and apply* go on) but its picture is frozen at the moment of the lock
/// (a snapshot: live values stop drawing), blurred 14 px (CSS `blur`, the
/// standard deviation) at saturation 0.6
/// under the dimmer `rgba(14,17,19,0.72)`, with no tickers and nothing in
/// the semantics tree. The card offers the key, the password and Log out.
class LockOverlay extends StatefulWidget {
  const LockOverlay({
    required this.child,
    this.card,
    this.onUnlock,
    this.onPassword,
    this.onLogOut,
    this.onActivity,
    super.key,
  });

  final Widget child;

  /// Null: Studio is not locked.
  final LockCardVm? card;

  /// The key; null when there is none.
  final VoidCallback? onUnlock;
  final ValueChanged<String>? onPassword;
  final VoidCallback? onLogOut;

  /// The person used Studio (a pointer or a key), at most once a second.
  final VoidCallback? onActivity;

  /// The dimmer and the saturation of the board.
  static const dimmer = Color.fromRGBO(14, 17, 19, 0.72);
  static const saturation = 0.6;

  @override
  State<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<LockOverlay> {
  final _snapshot = SnapshotController();
  var _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didUpdateWidget(LockOverlay old) {
    super.didUpdateWidget(old);
    final locked = widget.card != null;
    if (locked != (old.card != null)) {
      _snapshot
        ..clear()
        ..allowSnapshotting = locked;
    }
  }

  @override
  void initState() {
    super.initState();
    _snapshot.allowSnapshotting = widget.card != null;
  }

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  void _touch() {
    final now = DateTime.now();
    if (now.difference(_last) > const Duration(seconds: 1)) {
      _last = now;
      widget.onActivity?.call();
    }
  }

  /// The saturation matrix of CSS `saturate(s)`.
  static List<double> _saturate(double s) => [
    0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
    0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
    0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final locked = card != null;
    final shell = ExcludeSemantics(
      excluding: locked,
      child: TickerMode(
        enabled: !locked,
        child: ImageFiltered(
          enabled: locked,
          imageFilter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: .clamp),
            inner: ColorFilter.matrix(_saturate(LockOverlay.saturation)),
          ),
          child: SnapshotWidget(
            controller: _snapshot,
            mode: .permissive,
            child: widget.child,
          ),
        ),
      ),
    );
    return Listener(
      onPointerDown: (_) => _touch(),
      onPointerHover: (_) => _touch(),
      onPointerSignal: (_) => _touch(),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, _) {
          _touch();
          return .ignored;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(ignoring: locked, child: shell),
            ),
            if (card != null) ...[
              const Positioned.fill(
                child: ColoredBox(color: LockOverlay.dimmer),
              ),
              Positioned.fill(
                child: Center(
                  child: _LockCard(
                    vm: card,
                    onUnlock: widget.onUnlock,
                    onPassword: widget.onPassword,
                    onLogOut: widget.onLogOut,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LockCard extends StatefulWidget {
  const _LockCard({
    required this.vm,
    this.onUnlock,
    this.onPassword,
    this.onLogOut,
  });

  final LockCardVm vm;
  final VoidCallback? onUnlock;
  final ValueChanged<String>? onPassword;
  final VoidCallback? onLogOut;

  @override
  State<_LockCard> createState() => _LockCardState();
}

class _LockCardState extends State<_LockCard> {
  var _password = false;
  String? _typed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final usePassword = _password || vm.passwordOnly || widget.onUnlock == null;
    final link = TextStyle(
      fontSize: 13,
      color: c.text2,
      decoration: .underline,
      decorationColor: c.text2,
    );
    void submit() {
      final p = _typed ?? '';
      if (p.isNotEmpty) {
        widget.onPassword?.call(p);
      }
    }

    return Rise(
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: vm.title,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: c.ground1,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            border: Border.all(color: c.line1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 80,
                offset: Offset(0, 30),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: .min,
            spacing: 16,
            children: [
              CustomPaint(
                size: const Size.square(22),
                painter: LockGlyph(c.text4),
              ),
              Column(
                spacing: 6,
                children: [
                  Text(
                    vm.title,
                    textAlign: .center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  Text(
                    vm.text,
                    textAlign: .center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: c.text3),
                  ),
                ],
              ),
              if (usePassword)
                Column(
                  crossAxisAlignment: .stretch,
                  spacing: 12,
                  children: [
                    BoxedFormField(
                      vm: FieldVm(
                        value: _typed,
                        onChanged: (v) => _typed = v,
                        error: vm.error,
                        enabled: !vm.checking,
                      ),
                      label: vm.passwordLabel,
                      obscure: true,
                      border: c.emberLine,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: .done,
                      onSubmitted: (_) => submit(),
                    ),
                    OfferButton(
                      label: vm.unlock,
                      onPressed: submit,
                      busy: vm.checking,
                    ),
                  ],
                )
              else ...[
                UnlockButton(
                  glyph: vm.glyph,
                  label: vm.unlockLabel,
                  size: 92,
                  busy: vm.checking,
                  onPressed: widget.onUnlock,
                ),
                Text(
                  vm.unlockLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: .w600,
                    color: c.text1,
                  ),
                ),
              ],
              if (vm.kept case final k?)
                Text(
                  k,
                  textAlign: .center,
                  style: TextStyle(fontSize: 12, color: c.text4),
                ),
              Wrap(
                spacing: 20,
                alignment: .center,
                children: [
                  if (!usePassword)
                    InkWell(
                      onTap: () => setState(() => _password = true),
                      child: Text(vm.usePassword, style: link),
                    ),
                  InkWell(
                    onTap: widget.onLogOut,
                    child: Text(vm.logOut, style: link),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
