import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One action of an inspector: icon, title, one line of what it does, the
/// action's code name.
final class ActionRowVm extends Equatable {
  const ActionRowVm({
    required this.id,
    required this.title,
    this.icon,
    this.description,
    this.code,
    this.tone = Tone.neutral,
    this.disabledReason,
  });

  /// What the composer gets back on a tap.
  final String id;
  final String title;
  final String? icon;
  final String? description;

  /// `install_repo`, `deauthorize`, … in mono.
  final String? code;

  /// neutral, ember (primary) or bad (danger).
  final Tone tone;

  /// Set when the user cannot run it; the row is then disabled.
  final String? disabledReason;

  bool get enabled => disabledReason == null;

  @override
  List<Object?> get props => [
    id,
    title,
    icon,
    description,
    code,
    tone,
    disabledReason,
  ];
}

/// Board *Studio · Links* inspector actions: a card (ground/2, line/1,
/// radius 10) with the icon in a square, the title, one line, the code name;
/// a danger row is coral on the bad tint; a disabled row keeps its place,
/// dimmed, with the reason as its line.
class ActionRow extends StatelessWidget {
  const ActionRow({required this.vm, this.onTap, super.key});

  final ActionRowVm vm;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = vm.enabled && onTap != null;
    final danger = vm.tone == .bad;
    final warn = vm.tone == .warn;
    final title = switch (vm.tone) {
      _ when !vm.enabled => c.text4,
      .bad => c.badText,
      .ember => c.emberSoft,
      _ => c.text1,
    };
    final (bg, line) = switch (vm.tone) {
      _ when !vm.enabled => (c.ground1, c.line1),
      .bad => (c.badTint, c.badLine),
      .warn => (c.warnTint, c.warnLine),
      _ => (c.ground2, c.line1),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: line),
      ),
      child: InkWell(
        onTap: enabled ? () => onTap!(vm.id) : null,
        borderRadius: Radii.card,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              spacing: 12,
              children: [
                if (vm.icon case final i?)
                  Container(
                    width: 30,
                    height: 30,
                    alignment: .center,
                    decoration: BoxDecoration(
                      color: danger
                          ? c.badLine.withValues(alpha: 0.4)
                          : (warn ? c.warnLine : c.ground4),
                      borderRadius: Radii.segment,
                    ),
                    child: AppIcon(
                      i,
                      size: 16,
                      color: !vm.enabled
                          ? c.muted
                          : (danger ? c.bad : (warn ? c.warn : c.text2)),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    mainAxisSize: .min,
                    spacing: 2,
                    children: [
                      Text(
                        vm.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: .w500,
                          color: title,
                        ),
                      ),
                      if (vm.disabledReason ?? vm.description case final d?)
                        Text(
                          d,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: vm.enabled ? c.text3 : c.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (vm.code case final code?)
                  Text(code, style: mono(size: 10, color: c.text4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
