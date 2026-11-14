import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/quality_mark.dart';
import '../indicators/status_dot.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One tag of a found gateway: `used before` (good), `active + standby`
/// (ember), `downstream of <up>` (neutral), `new` (warn), `plain http`
/// (bad).
final class FoundTagVm extends Equatable {
  const FoundTagVm(this.label, this.tone);

  final String label;
  final Tone tone;

  @override
  List<Object?> get props => [label, tone];
}

/// What [FoundGatewayRow] draws (docs/design/specs/unlock-discover.md §4).
final class FoundGatewayRowVm extends Equatable {
  const FoundGatewayRowVm({
    required this.id,
    required this.site,
    required this.hosts,
    required this.note,
    this.tags = const [],
    this.dot = Tone.good,
    this.noteTone = Tone.neutral,
    this.seen = '',
    this.selected = false,
    this.enabled = true,
  });

  /// What a tap hands back: the site.
  final String id;
  final String site;
  final List<FoundTagVm> tags;

  /// `host:port · standby host:port`, in mono.
  final String hosts;

  /// `wyrmd <v> · <what is known of its CA>`, or why it is not offered.
  final String note;
  final Tone noteTone;
  final Tone dot;

  /// `now`, `2 s`.
  final String seen;
  final bool selected;

  /// A row that cannot be used is drawn at 60 % and does nothing.
  final bool enabled;

  @override
  List<Object?> get props => [
    id,
    site,
    tags,
    hosts,
    note,
    noteTone,
    dot,
    seen,
    selected,
    enabled,
  ];
}

/// A row of the *Find on this network* panel: padding 12 × 14, a 2 px left
/// edge (ember and `emberFill` when picked), a dot 8, the site 14/600 with
/// its tags (11/500, radius 6), the hosts in mono 12, the note 12 and the
/// time it was seen (11, `muted`) at the right.
class FoundGatewayRow extends StatelessWidget {
  const FoundGatewayRow({
    required this.vm,
    this.onTap,
    this.first = false,
    super.key,
  });

  final FoundGatewayRowVm vm;

  /// Picks [FoundGatewayRowVm.id]; ignored when the row is disabled.
  final VoidCallback? onTap;

  /// The first row has no top border.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: vm.selected,
      enabled: vm.enabled,
      child: Opacity(
        opacity: vm.enabled ? 1 : .6,
        child: Material(
          color: vm.selected ? c.emberFill : Colors.transparent,
          child: InkWell(
            onTap: vm.enabled ? onTap : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: first ? .none : BorderSide(color: c.ground3),
                  left: BorderSide(
                    color: vm.selected ? c.ember : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                spacing: 12,
                children: [
                  StatusDot(color: toneColor(c, vm.dot)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 3,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: .center,
                          children: [
                            Text(
                              vm.site,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: .w600,
                                color: c.text1,
                              ),
                            ),
                            for (final t in vm.tags) _Tag(t),
                          ],
                        ),
                        Text(
                          vm.hosts,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: c.text4,
                          ),
                        ),
                        Text(
                          vm.note,
                          style: TextStyle(
                            fontSize: 12,
                            color: switch (vm.noteTone) {
                              .warn => c.warn,
                              .bad => c.badText,
                              _ => c.text4,
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    vm.seen,
                    textAlign: .right,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.vm);

  final FoundTagVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (ground, ink) = switch (vm.tone) {
      .neutral => (c.ground4, c.text2),
      .bad => (c.badTint, c.badText),
      final t => (toneTint(c, t), toneColor(c, t)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(
        vm.label,
        style: TextStyle(fontSize: 11, fontWeight: .w500, color: ink),
      ),
    );
  }
}
