import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    disabledReason,
  ];
}

/// Board `SystemLog`, the toolbar: source, level, filter, lines, the
/// auto-refresh tick and `Get log`.
///
/// The filter reports a change when typing stops (400 ms) or on Enter; the
/// line count on Enter or when it loses the focus, kept inside its bounds.
class LogToolbar extends StatefulWidget {
  const LogToolbar({
    required this.vm,
    required this.onSource,
    required this.onLevel,
    required this.onFilter,
    required this.onLines,
    required this.onAuto,
    required this.onGet,
    super.key,
  });

  final LogToolbarVm vm;
  final ValueChanged<String> onSource;
  final ValueChanged<String> onLevel;
  final ValueChanged<String> onFilter;
  final ValueChanged<int> onLines;
  final ValueChanged<bool> onAuto;
  final VoidCallback onGet;

  @override
  State<LogToolbar> createState() => _LogToolbarState();
}

class _LogToolbarState extends State<LogToolbar> {
  late final _filter = TextEditingController(text: widget.vm.filter);
  late final _lines = TextEditingController(text: '${widget.vm.lines}');
  final _linesFocus = FocusNode();
  Timer? _typing;

  @override
  void initState() {
    super.initState();
    _linesFocus.addListener(() {
      if (!_linesFocus.hasFocus) {
        _commitLines();
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
  }

  @override
  void dispose() {
    _typing?.cancel();
    _filter.dispose();
    _lines.dispose();
    _linesFocus.dispose();
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

  BoxDecoration _box(AppColors c) => BoxDecoration(
    color: c.ground2,
    border: .all(color: c.line2),
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
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) => Container(
    height: 36,
    decoration: _box(c),
    alignment: Alignment.centerLeft,
    child: TextField(
      controller: controller,
      focusNode: focus,
      enabled: enabled,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: digits ? TextInputType.number : TextInputType.text,
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      cursorColor: c.ember,
      style: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 13,
        color: c.text1,
      ),
      decoration: InputDecoration(
        isCollapsed: true,
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
