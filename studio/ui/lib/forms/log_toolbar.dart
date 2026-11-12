import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../inputs/check_row.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What [LogToolbar] shows: the arguments of one `get_log`.
final class LogToolbarVm extends Equatable {
  const LogToolbarVm({
    required this.sourceLabel,
    required this.sources,
    required this.source,
    required this.levelLabel,
    required this.levels,
    required this.level,
    required this.filterLabel,
    required this.filterHint,
    required this.filter,
    required this.linesLabel,
    required this.lines,
    required this.autoLabel,
    required this.auto,
    required this.getLabel,
    this.aroundLabel = '',
    this.aroundHint = '',
    this.around = '',
    this.aroundClear = '',
    this.aroundBad = '',
    this.minLines = 1,
    this.maxLines = 2000,
    this.disabledReason,
  });

  final String sourceLabel;

  /// `broker (all)` (value `''`) and one entry per embedded link.
  final List<ChoiceItemVm<String>> sources;
  final String source;
  final String levelLabel;
  final List<ChoiceItemVm<String>> levels;
  final String level;
  final String filterLabel;
  final String filterHint;
  final String filter;
  final String linesLabel;
  final int lines;
  final int minLines;
  final int maxLines;
  final String autoLabel;
  final bool auto;
  final String getLabel;

  /// `Around (UTC)`: a time of day on the rows' clock. With one, the box
  /// shows only the lines near it (docs/design/specs/errors.md §3, *Open
  /// the log*).
  final String aroundLabel;

  /// `hh:mm:ss`.
  final String aroundHint;

  /// The time in force, `hh:mm:ss`; empty for none.
  final String around;

  /// The tooltip of the button that takes the time away.
  final String aroundClear;

  /// What the field says of text that is not a time.
  final String aroundBad;

  /// Why the log cannot be read (`needs config on sys`); usable when null.
  final String? disabledReason;

  @override
  List<Object?> get props => [
    sourceLabel,
    sources,
    source,
    levelLabel,
    levels,
    level,
    filterLabel,
    filterHint,
    filter,
    linesLabel,
    lines,
    minLines,
    maxLines,
    autoLabel,
    auto,
    getLabel,
    aroundLabel,
    aroundHint,
    around,
    aroundClear,
    aroundBad,
    disabledReason,
  ];
}

/// Board `SystemLog`, the toolbar: source, level, filter, lines, the
/// auto-refresh tick and `Get log`.
///
/// The filter reports a change when typing stops (400 ms) or on Enter; the
/// line count on Enter or when it loses the focus, kept inside its bounds.
/// The time (`Around`) reports `hh:mm:ss` on Enter or when it loses the
/// focus, and an empty text when it is cleared; text that is not a time is
/// marked and reports nothing.
class LogToolbar extends StatefulWidget {
  const LogToolbar({
    required this.vm,
    required this.onSource,
    required this.onLevel,
    required this.onFilter,
    required this.onLines,
    required this.onAuto,
    required this.onGet,
    this.onAround,
    super.key,
  });

  final LogToolbarVm vm;
  final ValueChanged<String> onSource;
  final ValueChanged<String> onLevel;
  final ValueChanged<String> onFilter;
  final ValueChanged<int> onLines;
  final ValueChanged<bool> onAuto;
  final VoidCallback onGet;

  /// The time changed: `hh:mm:ss`, or empty when it was cleared. The field
  /// is drawn only with this.
  final ValueChanged<String>? onAround;

  static final _clock = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$');

  /// [text] (`h:mm`, `hh:mm`, `hh:mm:ss`) as `hh:mm:ss`; null when it is
  /// not a time of day.
  static String? clock(String text) {
    final m = _clock.firstMatch(text.trim());
    if (m == null) {
      return null;
    }
    final parts = [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3) ?? '0'),
    ];
    if (parts[0] > 23 || parts[1] > 59 || parts[2] > 59) {
      return null;
    }
    return parts.map((n) => n.toString().padLeft(2, '0')).join(':');
  }

  @override
  State<LogToolbar> createState() => _LogToolbarState();
}

class _LogToolbarState extends State<LogToolbar> {
  late final _filter = TextEditingController(text: widget.vm.filter);
  late final _lines = TextEditingController(text: '${widget.vm.lines}');
  late final _around = TextEditingController(text: widget.vm.around);
  final _linesFocus = FocusNode();
  final _aroundFocus = FocusNode();
  Timer? _typing;

  /// The typed time is not one.
  var _aroundBad = false;

  /// The time last reported, until the view-model says its own.
  String? _reported;

  @override
  void initState() {
    super.initState();
    _linesFocus.addListener(() {
      if (!_linesFocus.hasFocus) {
        _commitLines();
      }
    });
    _aroundFocus.addListener(() {
      if (!_aroundFocus.hasFocus) {
        _commitAround();
      }
    });
  }

  @override
  void didUpdateWidget(LogToolbar old) {
    super.didUpdateWidget(old);
    if (widget.vm.lines != old.vm.lines &&
        int.tryParse(_lines.text) != widget.vm.lines) {
      _lines.text = '${widget.vm.lines}';
    }
    if (widget.vm.filter != old.vm.filter &&
        _filter.text != widget.vm.filter &&
        _typing == null) {
      _filter.text = widget.vm.filter;
    }
    // Set from outside (*Open the log*) or cleared.
    if (widget.vm.around != old.vm.around) {
      _reported = null;
      if (_around.text != widget.vm.around) {
        _around.text = widget.vm.around;
        _aroundBad = false;
      }
    }
  }

  @override
  void dispose() {
    _typing?.cancel();
    _filter.dispose();
    _lines.dispose();
    _around.dispose();
    _linesFocus.dispose();
    _aroundFocus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 400), _commitFilter);
  }

  void _commitFilter() {
    _typing?.cancel();
    _typing = null;
    if (_filter.text != widget.vm.filter) {
      widget.onFilter(_filter.text);
    }
  }

  void _commitAround() {
    final text = _around.text.trim();
    final time = text.isEmpty ? '' : LogToolbar.clock(text);
    if (time == null) {
      setState(() => _aroundBad = true);
      return;
    }
    if (_aroundBad) {
      setState(() => _aroundBad = false);
    }
    if (time != _around.text) {
      _around.text = time;
    }
    // Enter, then the focus leaving: one report of one time.
    if (time != (_reported ?? widget.vm.around)) {
      _reported = time;
      widget.onAround?.call(time);
    }
  }

  void _clearAround() {
    _around.clear();
    _commitAround();
  }

  void _commitLines() {
    final vm = widget.vm;
    final n = (int.tryParse(_lines.text) ?? vm.lines).clamp(
      vm.minLines,
      vm.maxLines,
    );
    if ('$n' != _lines.text) {
      _lines.text = '$n';
    }
    if (n != vm.lines) {
      widget.onLines(n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final enabled = vm.disabledReason == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 760;
          final filter = _labelled(
            c,
            vm.filterLabel,
            _input(
              c,
              controller: _filter,
              hint: vm.filterHint,
              enabled: enabled,
              onChanged: _typed,
              onSubmitted: (_) => _commitFilter(),
            ),
          );
          final controls = <Widget>[
            _labelled(
              c,
              vm.sourceLabel,
              _select(c, vm.sources, vm.source, 170, widget.onSource, enabled),
            ),
            _labelled(
              c,
              vm.levelLabel,
              _select(c, vm.levels, vm.level, 124, widget.onLevel, enabled),
            ),
            if (wide)
              Expanded(child: filter)
            else
              SizedBox(
                width: box.maxWidth,
                child: filter,
              ),
            if (widget.onAround != null)
              _labelled(
                c,
                vm.aroundLabel,
                SizedBox(
                  width: 124,
                  child: Tooltip(
                    message: _aroundBad ? vm.aroundBad : '',
                    child: _input(
                      c,
                      key: const ValueKey('log-around'),
                      controller: _around,
                      focus: _aroundFocus,
                      hint: vm.aroundHint,
                      enabled: enabled,
                      bad: _aroundBad,
                      mono: true,
                      onSubmitted: (_) => _commitAround(),
                      trailing: vm.around.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('log-around-clear'),
                              tooltip: vm.aroundClear,
                              visualDensity: .compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                              onPressed: _clearAround,
                              icon: AppIcon(
                                'err_close',
                                size: 12,
                                color: c.text3,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            _labelled(
              c,
              vm.linesLabel,
              SizedBox(
                width: 90,
                child: _input(
                  c,
                  controller: _lines,
                  focus: _linesFocus,
                  enabled: enabled,
                  digits: true,
                  onSubmitted: (_) => _commitLines(),
                ),
              ),
            ),
            SizedBox(
              height: 36,
              child: IntrinsicWidth(
                child: CheckRow(
                  vm: FieldVm(
                    value: vm.auto,
                    onChanged: widget.onAuto,
                    enabled: enabled,
                  ),
                  label: vm.autoLabel,
                ),
              ),
            ),
            Button.primary(
              label: vm.getLabel,
              onPressed: enabled ? widget.onGet : null,
              disabledReason: vm.disabledReason,
              size: ButtonSize.compact,
              fontSize: 13,
            ),
          ];
          return wide
              ? Row(
                  crossAxisAlignment: .end,
                  spacing: 12,
                  children: controls,
                )
              : Wrap(
                  crossAxisAlignment: .end,
                  spacing: 12,
                  runSpacing: 12,
                  children: controls,
                );
        },
      ),
    );
  }

  Widget _labelled(AppColors c, String label, Widget control) => Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 6,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: c.text3)),
      control,
    ],
  );

  BoxDecoration _box(AppColors c, {bool bad = false}) => BoxDecoration(
    color: c.ground2,
    border: .all(color: bad ? c.bad : c.line2),
    borderRadius: Radii.input,
  );

  Widget _select(
    AppColors c,
    List<ChoiceItemVm<String>> items,
    String value,
    double minWidth,
    ValueChanged<String> onChanged,
    bool enabled,
  ) {
    final label = items
        .where((i) => i.value == value)
        .map((i) => i.label)
        .firstOrNull;
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: '',
      position: .under,
      color: c.ground2,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.control,
        side: BorderSide(color: c.line2),
      ),
      constraints: BoxConstraints(minWidth: minWidth),
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final i in items)
          PopupMenuItem(
            value: i.value,
            height: 36,
            child: Text(
              i.label,
              style: TextStyle(fontSize: 13, color: c.text1),
            ),
          ),
      ],
      child: Container(
        height: 36,
        width: minWidth,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: _box(c),
        child: Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                label ?? value,
                maxLines: 1,
                overflow: .ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: enabled ? c.text1 : c.muted,
                ),
              ),
            ),
            AppIcon('ui_chevron_down', size: 14, color: c.text3),
          ],
        ),
      ),
    );
  }

  Widget _input(
    AppColors c, {
    required TextEditingController controller,
    required bool enabled,
    FocusNode? focus,
    String? hint,
    bool digits = false,
    bool bad = false,
    bool mono = false,
    Key? key,
    Widget? trailing,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) => Container(
    height: 36,
    decoration: _box(c, bad: bad),
    alignment: Alignment.centerLeft,
    child: TextField(
      key: key,
      controller: controller,
      focusNode: focus,
      enabled: enabled,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: digits ? TextInputType.number : TextInputType.text,
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      cursorColor: c.ember,
      style: TextStyle(
        fontFamily: mono ? AppFonts.mono : AppFonts.sans,
        fontSize: 13,
        color: c.text1,
      ),
      decoration: InputDecoration(
        isCollapsed: true,
        suffixIcon: trailing,
        suffixIconConstraints: const BoxConstraints(
          maxWidth: 32,
          maxHeight: 32,
        ),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13,
          color: c.text4,
        ),
      ),
    ),
  );
}
