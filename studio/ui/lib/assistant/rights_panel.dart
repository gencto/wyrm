import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/fact_grid.dart';
import '../containers/section_label.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'blocked.dart';
import 'task_badge.dart';

/// One mode of *Who approves*.
final class ModeVm extends Equatable {
  const ModeVm(this.mode, {this.selected = false});

  final AgentModeVm mode;
  final bool selected;

  String get label => mode.label;
  String get detail => mode.detail;

  @override
  List<Object?> get props => [mode, selected];
}

/// Whether the secret the agent's `api_key_ref` names is set.
enum ApiKeyState {
  set,
  notSet,

  /// Not known: the names need `config` on the link.
  unknown,
}

/// One prefix the agent may propose changes under: the full [prefix] and
/// its [label] below the site.
final class PrefixRowVm extends Equatable {
  const PrefixRowVm(this.prefix, this.label);

  final String prefix;
  final String label;

  @override
  List<Object?> get props => [prefix, label];
}

/// What [RightsPanel] draws.
final class RightsPanelVm extends Equatable {
  const RightsPanelVm({
    required this.modes,
    required this.prefixes,
    this.agent,
    this.model,
    this.used,
    this.budget,
    this.apiKeyRef,
    this.apiKey = ApiKeyState.unknown,
    this.sentTo,
    this.blocked,
    this.staged = false,
    this.modeUnknown = false,
  });

  final List<ModeVm> modes;

  /// Where it may propose changes: full key prefixes.
  final List<String> prefixes;

  /// The agent link's id; null when the site has none.
  final String? agent;

  /// The model it asks.
  final String? model;

  /// LLM tokens used today, and its daily budget.
  final num? used;
  final num? budget;

  /// The name of the secret of its API key, and whether it is set.
  final String? apiKeyRef;
  final ApiKeyState apiKey;

  /// Where its requests go.
  final String? sentTo;

  /// Why the modes and prefixes cannot be edited; null: they can.
  final Blocked? blocked;

  /// A change of its params is staged.
  final bool staged;

  /// Who approves is not known (the agent's settings did not read): no
  /// mode is marked, and the panel says so with its caution.
  final bool modeUnknown;

  String? get unknownNote => modeUnknown ? AgentModeVm.unknown.caution : null;

  String get modesLabel => S.current.mayDoModes;
  String get prefixesLabel => S.current.prefixesLabel;
  String get prefixesNote => S.current.prefixesNote;

  /// `+ prefix`; null without an agent.
  String? get addPrefix => agent == null ? null : S.current.addPrefix;

  String get note => S.current.mayDoEditNote;
  String? get editReason => blocked?.text;
  String? get stagedNote => staged ? S.current.paramsStaged : null;

  /// A prefix and its chip's words (below the site).
  List<PrefixRowVm> get prefixRows => [
    for (final p in prefixes)
      PrefixRowVm(
        p,
        p.split('/').length > 2 ? p.split('/').skip(2).join('/') : p,
      ),
  ];

  /// The model, today's budget, the API key and where it is sent.
  List<FactVm> get facts => [
    if (model case final m?)
      FactVm(label: S.current.cfgModel, value: m, mono: true),
    FactVm(
      label: S.current.factToday,
      value: S.current.todayUsed(_tokens(used), _tokens(budget)),
    ),
    if (apiKeyRef case final ref?)
      FactVm(
        label: S.current.cfgApiKey,
        value: switch (apiKey) {
          ApiKeyState.set => S.current.apiKeySet,
          ApiKeyState.notSet => S.current.apiKeyNotSet,
          ApiKeyState.unknown => S.current.apiKeyUnknown(agent ?? 'agent'),
        },
        code: ref,
      ),
    if (sentTo case final h?)
      FactVm(label: S.current.factSentTo, value: h, mono: true),
  ];

  /// `182 k`, `1 M`, `950`, `—`: tokens as the board writes them.
  static String _tokens(num? n) => switch (n) {
    null => '—',
    >= 1000000 => '${plainNumber((n / 100000).round() / 10)} M',
    >= 1000 => '${(n / 1000).round()} k',
    final n => '${n.round()}',
  };

  @override
  List<Object?> get props => [
    modes,
    prefixes,
    agent,
    model,
    used,
    budget,
    apiKeyRef,
    apiKey,
    sentTo,
    blocked,
    staged,
    modeUnknown,
  ];
}

/// Board *AssistantRights*: who approves (the three modes), where the agent
/// may propose changes (prefix chips), the model, today's budget, the API
/// key (set or not, never shown) and where it is sent. A pick stages an
/// update of the agent link's params; Review applies it.
class RightsPanel extends StatelessWidget {
  const RightsPanel({
    required this.vm,
    this.onMode,
    this.onRemovePrefix,
    this.onAddPrefix,
    super.key,
  });

  final RightsPanelVm vm;
  final ValueChanged<AgentModeVm>? onMode;
  final ValueChanged<String>? onRemovePrefix;
  final VoidCallback? onAddPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(
      fontSize: FontSizes.xs,
      height: 1.4,
      color: c.text3,
    );
    final can = vm.editReason == null;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        SectionLabel(vm.modesLabel),
        for (final m in vm.modes)
          Tooltip(
            message: vm.editReason ?? '',
            child: Material(
              color: m.selected ? c.emberTint : Colors.transparent,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: m.selected ? c.ember : c.line1,
                  width: m.selected ? 1.5 : 1,
                ),
                borderRadius: Radii.control,
              ),
              child: InkWell(
                onTap: can && !m.selected && onMode != null
                    ? () => onMode!(m.mode)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: .start,
                    spacing: 10,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: .circle,
                          border: Border.all(
                            color: m.selected ? c.ember : c.text4,
                            width: 2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          spacing: 2,
                          children: [
                            Text(
                              m.label,
                              style: TextStyle(
                                fontSize: FontSizes.md,
                                color: c.text1,
                              ),
                            ),
                            Text(m.detail, style: small),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (vm.unknownNote case final u?)
          Container(
            padding: Insets.band,
            decoration: BoxDecoration(
              color: c.warnTint,
              border: Border.all(color: c.warnLine),
              borderRadius: Radii.control,
            ),
            child: Text(u, style: small.copyWith(color: c.warn)),
          ),
        const SizedBox(height: 10),
        SectionLabel(vm.prefixesLabel),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: .center,
          children: [
            for (final PrefixRowVm(prefix: p, :label) in vm.prefixRows)
              Container(
                height: 24,
                constraints: const BoxConstraints(maxWidth: 260),
                padding: Insets.chip,
                decoration: BoxDecoration(
                  color: c.ground3,
                  border: Border.all(color: c.line2),
                  borderRadius: Radii.chip,
                ),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: p,
                        child: Text(
                          label,
                          overflow: .ellipsis,
                          style: mono(size: 11, color: c.text1),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: vm.editReason ?? '',
                      child: InkWell(
                        onTap: can && onRemovePrefix != null
                            ? () => onRemovePrefix!(p)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: AppIcon(
                            'ui_close',
                            size: 11,
                            color: can ? c.text3 : c.text4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (vm.addPrefix case final a?)
              Tooltip(
                message: vm.editReason ?? '',
                child: InkWell(
                  onTap: can ? onAddPrefix : null,
                  child: Padding(
                    padding: Insets.textLink,
                    child: Text(
                      a,
                      style: TextStyle(
                        fontSize: FontSizes.sm,
                        color: can ? c.text2 : c.text4,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Text(vm.prefixesNote, style: small),
        if (vm.stagedNote case final s?)
          Container(
            padding: Insets.band,
            decoration: BoxDecoration(
              color: c.warnTint,
              border: Border.all(color: c.warnLine),
              borderRadius: Radii.control,
            ),
            child: Text(s, style: small.copyWith(color: c.warn)),
          ),
        const SizedBox(height: 10),
        FactGrid(facts: vm.facts, labelWidth: 96),
        Text(vm.note, style: small),
      ],
    );
  }
}
