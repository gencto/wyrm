import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

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

/// 48 high and up; disabled rows keep their place and say why.
class ActionRow extends StatelessWidget {
  const ActionRow({required this.vm, this.onTap, super.key});

  final ActionRowVm vm;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = vm.enabled && onTap != null;
    final title = switch (vm.tone) {
      _ when !vm.enabled => c.muted,
      .bad => c.badText,
      .ember => c.emberSoft,
      _ => c.text1,
    };
    final row = InkWell(
      onTap: enabled ? () => onTap!(vm.id) : null,
      borderRadius: Radii.segment,
      hoverColor: c.ground3,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            spacing: 12,
            children: [
              if (vm.icon case final i?)
                AppIcon(
                  i,
                  size: 18,
                  color: vm.enabled
                      ? (vm.tone == .bad ? c.bad : c.text3)
                      : c.muted,
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
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: vm.enabled ? c.text3 : c.text4,
                        ),
                      ),
                  ],
                ),
              ),
              if (vm.code case final code?)
                Text(code, style: mono(size: 11, color: c.text4)),
            ],
          ),
        ),
      ),
    );
    return vm.enabled ? row : Tooltip(message: vm.disabledReason, child: row);
  }
}
