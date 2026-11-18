import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/typography.dart';

/// A labelled text field in a box, as the log-in board draws its fields
/// (docs/design/specs/login.md §3): the label (13, `text2`) 8 above a box
/// 46 high, radius 10, filled `ground2`, bordered `line2` — `badLine` while it
/// is [alert] or holds an error — and the error (13, `badText`) 8 under it.
///
/// Controlled: what the field shows is [FieldVm.value]. A value set from
/// outside (a recent-gateway chip, a password the store cleared) is written
/// into the field, also while it has the focus; while the user types, the
/// value that comes back is the text itself and nothing is written. The
/// error under the field is that of the text shown. [obscure] hides the
/// text, spaced 0.2 em, with an eye button 36 × 36 inside on the right that
/// shows it.
class BoxedFormField extends StatefulWidget {
  const BoxedFormField({
    required this.vm,
    required this.label,
    this.leading,
    this.trailing,
    this.mono = false,
    this.obscure = false,
    this.alert = false,
    this.focusNode,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.onLeave,
    this.hint,
    this.border,
    this.beside,
    super.key,
  });

  final FieldVm<String?> vm;
  final String label;

  /// Before the text (the gateway's status dot), 10 apart.
  final Widget? leading;

  /// After the text (the gateway's spinner), 10 apart.
  final Widget? trailing;

  /// Mono 13 (a URL) instead of sans 15.
  final bool mono;

  /// A password: hidden, with the show/hide eye.
  final bool obscure;

  /// Draw the border in the alert colour (unreachable, wrong password).
  final bool alert;

  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// The field lost the focus (the gateway is probed then).
  final VoidCallback? onLeave;

  /// Shown in `text4` while the field is empty (`https://host:port`).
  final String? hint;

  /// The border's colour instead of `line2` (amber while a found gateway's
  /// CA waits for its check); [alert] and an error still win.
  final Color? border;

  /// Beside the box, 8 to its right and as high (`Find on this network`).
  final Widget? beside;

  @override
  State<BoxedFormField> createState() => _BoxedFormFieldState();
}

class _BoxedFormFieldState extends State<BoxedFormField> {
  late final _text = TextEditingController(text: widget.vm.value ?? '');
  final _field = GlobalKey<FormFieldState<String?>>();
  FocusNode? _ownFocus;
  var _hidden = true;

  /// The validator ran on this field (the `Form` validates every field once
  /// one was edited, and on a submit): a value from outside is judged again.
  var _validated = false;

  /// The text shown, as the view-model holds it (empty is none).
  String? get _shown => _text.text.isEmpty ? null : _text.text;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(BoxedFormField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    final value = widget.vm.value ?? '';
    // From outside: a value that is not the text. While the field has the
    // focus, only a value that moved is: the text typed comes back as it is,
    // or as the store keeps it (the gateway field trims it), and rewriting
    // that under the cursor would take the user's spaces and commas.
    final outside =
        value != _text.text &&
        (!_focus.hasFocus || (old.vm.value ?? '') != value);
    if (outside) {
      // The controller, not the form state: `didChange` would mark the
      // enclosing `Form` dirty while the tree is being built ("setState()
      // called during build": the frame was dropped and the log-in page kept
      // the pixels of earlier ones).
      // The cursor after the text: the field may have the focus.
      _text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      // The `Form` judged this field in its own build, before the new
      // value reached it: an error shown is judged again, on this field
      // only (a descendant of the one being built, so allowed).
      if (_validated) {
        _field.currentState?.validate();
      }
    }
  }

  void _onFocus() {
    if (!_focus.hasFocus) {
      widget.onLeave?.call();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    _text.dispose();
    super.dispose();
  }

  Widget _beside(Widget box) => switch (widget.beside) {
    null => box,
    final b => Row(
      spacing: 8,
      children: [
        Expanded(child: box),
        b,
      ],
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hidden = widget.obscure && _hidden;
    return FormField<String?>(
      key: _field,
      initialValue: widget.vm.value,
      // What is judged is the text the field shows. The `Form` validates in
      // its own build, before this field takes its new view-model: typed or
      // filled by AutoFill, the text is already new there, the view-model's
      // value is still the one before (owner, 2026-11-19: a password shown
      // with "Required field" under it). A value from outside reaches the
      // text in `didUpdateWidget`, which judges it again.
      validator: switch (widget.vm.validator) {
        final v? => (_) {
          _validated = true;
          return v(_shown);
        },
        null => null,
      },
      enabled: widget.vm.enabled,
      builder: (state) {
        final error = widget.vm.error ?? state.errorText;
        final style = widget.mono
            ? TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: FontSizes.md,
                height: LineHeights.title,
                letterSpacing: Trackings.none,
                color: c.text1,
              )
            : TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: FontSizes.xl,
                height: LineHeights.title,
                color: c.text1,
                // 0.2 em while hidden; none of the theme's spacing otherwise.
                letterSpacing: hidden ? Trackings.hiddenSecret : Trackings.none,
              );
        return Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            Text(
              widget.label,
              style: TextStyle(fontSize: FontSizes.md, color: c.text2),
            ),
            _beside(
              Container(
                height: 46,
                padding: EdgeInsets.only(
                  left: widget.leading == null ? 14 : 12,
                  right: widget.obscure
                      ? 6
                      : (widget.leading == null ? 14 : 12),
                ),
                decoration: BoxDecoration(
                  color: c.ground2,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppRadii.card),
                  ),
                  border: .all(
                    color: widget.alert || error != null
                        ? c.badLine
                        : widget.border ?? c.line2,
                  ),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    ?widget.leading,
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        enabled: widget.vm.enabled,
                        obscureText: hidden,
                        keyboardType: widget.keyboardType,
                        autofillHints: widget.autofillHints,
                        textInputAction: widget.textInputAction,
                        style: style,
                        cursorColor: c.ember,
                        cursorHeight: widget.mono ? 16 : 18,
                        inputFormatters: widget.mono
                            ? [FilteringTextInputFormatter.deny('\n')]
                            : null,
                        // The box is drawn above: nothing of the theme's
                        // input decoration inside it.
                        decoration: InputDecoration(
                          isCollapsed: true,
                          hintText: widget.hint,
                          hintStyle: style.copyWith(color: c.text4),
                          filled: false,
                          // The board's inputs without their own padding keep
                          // the browser's 2 px on each side.
                          contentPadding:
                              widget.leading != null || widget.obscure
                              ? const EdgeInsets.symmetric(
                                  horizontal: 2,
                                )
                              : .zero,
                          border: .none,
                          enabledBorder: .none,
                          focusedBorder: .none,
                          disabledBorder: .none,
                          errorBorder: .none,
                          focusedErrorBorder: .none,
                        ),
                        onChanged: (v) {
                          state.didChange(v.isEmpty ? null : v);
                          widget.vm.onChanged(v.isEmpty ? null : v);
                        },
                        onSubmitted: widget.onSubmitted,
                      ),
                    ),
                    ?widget.trailing,
                    if (widget.obscure)
                      SizedBox.square(
                        dimension: AppSizes.fieldEye,
                        child: IconButton(
                          padding: .zero,
                          tooltip: _hidden
                              ? S.current.showPassword
                              : S.current.hidePassword,
                          style: IconButton.styleFrom(
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(AppRadii.control),
                              ),
                            ),
                          ),
                          onPressed: () => setState(() => _hidden = !_hidden),
                          icon: CustomPaint(
                            size: const Size.square(18),
                            painter: _Eye(c.text4, slashed: !_hidden),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Text(
                error,
                style: TextStyle(fontSize: FontSizes.md, color: c.badText),
              ),
          ],
        );
      },
    );
  }
}

/// The board's eye: `M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z` and a
/// circle r 3 in a 24 × 24 box, stroke 1.8; slashed while the text shows.
class _Eye extends CustomPainter {
  _Eye(this.color, {required this.slashed});

  final Color color;
  final bool slashed;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1.8
      ..strokeCap = .round
      ..strokeJoin = .round;
    canvas
      ..save()
      ..scale(k)
      ..drawPath(
        Path()
          ..moveTo(2, 12)
          ..cubicTo(2, 12, 5.6, 5, 12, 5)
          ..cubicTo(18.4, 5, 22, 12, 22, 12)
          ..cubicTo(22, 12, 18.4, 19, 12, 19)
          ..cubicTo(5.6, 19, 2, 12, 2, 12)
          ..close(),
        paint,
      )
      ..drawCircle(const Offset(12, 12), 3, paint);
    if (slashed) {
      canvas.drawLine(const Offset(3, 3), const Offset(21, 21), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Eye old) => old.color != color || old.slashed != slashed;
}
