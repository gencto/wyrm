import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/found_gateway_row.dart';
import '../indicators/arc_spinner.dart';
import '../inputs/range_probe.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';

/// One reason of the empty panel, with its dot and, for the local-network
/// permission on macOS and iOS, `Open settings`.
final class DiscoverReasonVm extends Equatable {
  const DiscoverReasonVm(this.text, {this.tone = Tone.warn, this.settings});

  final String text;

  /// warn, neutral (grey) or good (teal).
  final Tone tone;

  /// The link after the text; null for none.
  final String? settings;

  @override
  List<Object?> get props => [text, tone, settings];
}

/// The empty panel: what was not found, why, and *Probe a range*.
final class DiscoverNoneVm extends Equatable {
  const DiscoverNoneVm({
    required this.title,
    required this.reasons,
    required this.range,
    required this.port,
  });

  /// `No gateway answered on <where> in 8 s`.
  final String title;
  final List<DiscoverReasonVm> reasons;
  final FieldVm<String?> range;
  final FieldVm<String?> port;

  @override
  List<Object?> get props => [title, reasons, range, port];
}

/// What [DiscoverPanel] draws (docs/design/specs/unlock-discover.md §4).
final class DiscoverPanelVm extends Equatable {
  const DiscoverPanelVm({
    required this.title,
    this.scanning = false,
    this.rows = const [],
    this.none,
  });

  /// `Looking on …`, `n gateways on … · announced by
  /// DNS-SD`, or `Nothing found`.
  final String title;

  /// The browse or the probe runs: the spinner before the title.
  final bool scanning;
  final List<FoundGatewayRowVm> rows;

  /// Set when the search ended with no row.
  final DiscoverNoneVm? none;

  @override
  List<Object?> get props => [title, scanning, rows, none];
}

/// The panel under the gateway field while *Find on this network* is on: a
/// card (radius 12, `line1`, `ground1`) with its header (the spinner, the
/// title, `Look again`), then the rows as they answer, or the empty state.
class DiscoverPanel extends StatelessWidget {
  const DiscoverPanel({
    required this.vm,
    required this.onLookAgain,
    required this.onPick,
    required this.onProbe,
    this.onOpenSettings,
    super.key,
  });

  final DiscoverPanelVm vm;
  final VoidCallback onLookAgain;

  /// A row was picked: its [FoundGatewayRowVm.id].
  final ValueChanged<String> onPick;
  final VoidCallback onProbe;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: S.current.discoverPanel,
      child: Container(
        clipBehavior: .antiAlias,
        decoration: BoxDecoration(
          color: c.ground1,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: .all(color: c.line1),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.ground3)),
              ),
              child: Row(
                spacing: 10,
                children: [
                  if (vm.scanning)
                    ArcSpinner(
                      color: c.ember,
                      size: 14,
                      strokeWidth: 2.6,
                      label: vm.title,
                    ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        vm.title,
                        style: TextStyle(fontSize: 13, color: c.text2),
                      ),
                    ),
                  ),
                  _Link(
                    S.current.lookAgain,
                    onTap: onLookAgain,
                    color: c.text4,
                    size: 12,
                  ),
                ],
              ),
            ),
            for (final (i, r) in vm.rows.indexed)
              FoundGatewayRow(
                vm: r,
                first: i == 0,
                onTap: () => onPick(r.id),
              ),
            if (vm.none case final none?) _none(context, none),
          ],
        ),
      ),
    );
  }

  Widget _none(BuildContext context, DiscoverNoneVm none) {
    final c = context.colors;
    final text = TextStyle(
      fontSize: 13,
      height: 1.45,
      leadingDistribution: .even,
      color: c.text2,
    );
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text(none.title, style: TextStyle(fontSize: 14, color: c.badText)),
          Column(
            crossAxisAlignment: .stretch,
            spacing: 8,
            children: [
              for (final r in none.reasons)
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
                          shape: .circle,
                          color: switch (r.tone) {
                            .good => c.good,
                            .warn => c.warn,
                            _ => c.muted,
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: r.text),
                            if (r.settings case final s?
                                when onOpenSettings != null) ...[
                              const TextSpan(text: ' '),
                              WidgetSpan(
                                alignment: .baseline,
                                baseline: .alphabetic,
                                child: _Link(
                                  s,
                                  onTap: onOpenSettings!,
                                  color: c.emberSoft,
                                  size: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                        style: text,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.ground3)),
            ),
            child: RangeProbe(
              range: none.range,
              port: none.port,
              onProbe: onProbe,
            ),
          ),
        ],
      ),
    );
  }
}

/// An underlined text button.
class _Link extends StatelessWidget {
  const _Link(
    this.label, {
    required this.onTap,
    required this.color,
    required this.size,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          label,
          style: TextStyle(
            fontSize: size,
            color: color,
            decoration: .underline,
            decorationColor: color,
          ),
        ),
      ),
    ),
  );
}
