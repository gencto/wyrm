import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// A labelled text field in a box, as the log-in board draws its fields
/// (docs/design/specs/login.md §3): the label (13, `text2`) 8 above a box
/// 46 high, radius 10, filled `ground2`, bordered `line2` — `badLine` while it
/// is [alert] or holds an error — and the error (13, `badText`) 8 under it.
///
/// Controlled: [FieldVm.value] is written back into the field whenever it
/// changes from outside while the field is not focused (a recent-gateway chip
/// fills the gateway field). [obscure] hides the text, spaced 0.2 em, with an
/// eye button 36 × 36 inside on the right that shows it.
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

  @override
  State<BoxedFormField> createState() => _BoxedFormFieldState();
}

class _BoxedFormFieldState extends State<BoxedFormField> {
  late final _text = TextEditingController(text: widget.vm.value ?? '');
  final _field = GlobalKey<FormFieldState<String?>>();
  FocusNode? _ownFocus;
  var _hidden = true;

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
    if (!_focus.hasFocus && value != _text.text) {
      _text.text = value;
      // The form validates what it holds, not what the controller shows.
      _field.currentState?.didChange(widget.vm.value);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hidden = widget.obscure && _hidden;
    return FormField<String?>(
      key: _field,
      initialValue: widget.vm.value,
      validator: widget.vm.validator,
      enabled: widget.vm.enabled,
      builder: (state) {
        final error = widget.vm.error ?? state.errorText;
        final style = widget.mono
            ? TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 13,
                height: 1.3,
                letterSpacing: 0,
                color: c.text1,
              )
            : TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 15,
                height: 1.3,
                color: c.text1,
                // 0.2 em while hidden; none of the theme's spacing otherwise.
                letterSpacing: hidden ? 3 : 0,
              );
        return Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            Text(widget.label, style: TextStyle(fontSize: 13, color: c.text2)),
            Container(
              height: 46,
              padding: EdgeInsets.only(
                left: widget.leading == null ? 14 : 12,
                right: widget.obscure ? 6 : (widget.leading == null ? 14 : 12),
              ),
              decoration: BoxDecoration(
                color: c.ground2,
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                border: .all(
                  color: widget.alert || error != null ? c.badLine : c.line2,
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
                        filled: false,
                        // The board's inputs without their own padding keep
                        // the browser's 2 px on each side.
                        contentPadding: widget.leading != null || widget.obscure
                            ? const EdgeInsets.symmetric(horizontal: 2)
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
                      dimension: 36,
                      child: IconButton(
                        padding: .zero,
                        tooltip: _hidden
                            ? S.current.showPassword
                            : S.current.hidePassword,
                        style: IconButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
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
            if (error != null)
              Text(
                error,
                style: TextStyle(fontSize: 13, color: c.badText),
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
