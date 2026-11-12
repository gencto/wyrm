import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../forms/param_form.dart';
import '../inputs/switch_row.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'fact_grid.dart';

/// One section of an inspector (docs/design/specs/explorer.md §4): an
/// uppercase label with an optional ember note on its right, then any of
/// fields in [columns], a segmented choice, facts and code lines.
final class InspectorSectionVm extends Equatable {
  const InspectorSectionVm({
    required this.label,
    this.note,
    this.fields = const [],
    this.columns = 2,
    this.segments = const [],
    this.segment,
    this.onSegment,
    this.segmentsReason,
    this.facts = const [],
    this.code = const [],
    this.text,
  });

  final String label;

  /// `staged · was 1 s`, in ember with a dot.
  final String? note;

  /// Fields from `~meta.cfg`; a toggle is a row with its description.
  final List<ParamFieldVm> fields;
  final int columns;

  /// A segmented choice (`250 ms`, `500 ms`, `1 s`, `5 s`).
  final List<String> segments;

  /// The index of the chosen segment, null when none is.
  final int? segment;

  /// Behaviour: out of [props]. Null disables the segments.
  final ValueChanged<int>? onSegment;

  /// Why the segments are disabled.
  final String? segmentsReason;
  final List<FactVm> facts;

  /// `(~meta, {type: number, …})` lines on the dark code ground.
  final List<(String, String)> code;

  /// One grey line at the end.
  final String? text;

  @override
  List<Object?> get props => [
    label,
    note,
    fields,
    columns,
    segments,
    segment,
    onSegment != null,
    segmentsReason,
    facts,
    code,
    text,
  ];
}

/// The sections of an inspector, 18 apart.
class InspectorSections extends StatelessWidget {
  const InspectorSections({required this.sections, super.key});

  final List<InspectorSectionVm> sections;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 18,
      children: [for (final s in sections) _section(c, s)],
    );
  }

  Widget _section(AppColors c, InspectorSectionVm s) {
    final toggles = [
      for (final f in s.fields)
        if (f.kind == .toggle) f,
    ];
    final others = [
      for (final f in s.fields)
        if (f.kind != .toggle) f,
    ];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: .w600,
                  letterSpacing: 0.72,
                  color: c.text4,
                ),
              ),
            ),
            if (s.note case final n?)
              Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: .circle, color: c.ember),
                  ),
                  Text(n, style: TextStyle(fontSize: 12, color: c.emberSoft)),
                ],
              ),
          ],
        ),
        if (others.isNotEmpty) ParamForm(fields: others, columns: s.columns),
        for (final t in toggles) _toggle(c, t),
        if (s.segments.isNotEmpty) _segments(c, s),
        if (s.facts.isNotEmpty) FactGrid(facts: s.facts),
        if (s.code.isNotEmpty) _code(c, s.code),
        if (s.text case final t?)
          Text(t, style: TextStyle(fontSize: 12, color: c.text4)),
      ],
    );
  }

  Widget _toggle(AppColors c, ParamFieldVm f) => Row(
    spacing: 12,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: .start,
          spacing: 2,
          children: [
            Text(f.label, style: TextStyle(fontSize: 14, color: c.text1)),
            if (f.description case final d?)
              Text(d, style: TextStyle(fontSize: 12, color: c.text4)),
          ],
        ),
      ),
      AppSwitch(
        value: f.value == true,
        onChanged: f.enabled ? f.onChanged : null,
      ),
    ],
  );

  Widget _segments(AppColors c, InspectorSectionVm s) {
    final bar = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.ground3,
        border: .all(color: c.line1),
        borderRadius: Radii.button,
      ),
      child: Row(
        spacing: 3,
        children: [
          for (final (i, label) in s.segments.indexed)
            Expanded(
              child: InkWell(
                onTap: s.onSegment == null ? null : () => s.onSegment!(i),
                borderRadius: Radii.segment,
                child: Container(
                  height: 34,
                  alignment: .center,
                  decoration: BoxDecoration(
                    color: i == s.segment ? c.line2 : null,
                    borderRadius: Radii.segment,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == s.segment ? .w600 : .w400,
                      color: s.onSegment == null
                          ? c.muted
                          : (i == s.segment ? c.text1 : c.text3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return s.onSegment == null && s.segmentsReason != null
        ? Tooltip(message: s.segmentsReason, child: bar)
        : bar;
  }

  Widget _code(AppColors c, List<(String, String)> lines) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: c.ground0,
      border: .all(color: c.line1),
      borderRadius: Radii.button,
    ),
    child: SelectableText.rich(
      TextSpan(
        children: [
          for (final (i, (label, text)) in lines.indexed) ...[
            if (i > 0) const TextSpan(text: '\n'),
            TextSpan(
              text: '$label ',
              style: TextStyle(color: c.text4),
            ),
            TextSpan(text: text),
          ],
        ],
      ),
      style: mono(size: 12, color: c.text2).copyWith(height: 1.7),
    ),
  );
}
