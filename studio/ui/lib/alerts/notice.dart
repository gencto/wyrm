import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// A notice: what happened, in the tone of the outcome.
final class NoticeVm extends Equatable {
  const NoticeVm({required this.message, required this.tone, this.detail});

  final String message;
  final Tone tone;

  /// The broker's own words or a key, in mono under the message.
  final String? detail;

  @override
  List<Object?> get props => [message, tone, detail];
}

/// Board *Design system* §06 notices: radius 8, the tone's tint and line.
class Notice extends StatelessWidget {
  const Notice({required this.vm, super.key});

  final NoticeVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, line, fg, icon) = switch (vm.tone) {
      .good => (c.goodTint, c.goodLine, const Color(0xFFC4EBE1), 'ui_check'),
      .bad => (c.badTint, c.badLine, const Color(0xFFF0C2B5), 'ui_close'),
      .warn => (c.warnTint, c.warnLine, c.warn, 'ui_spinner'),
      .ember => (c.emberTint, c.emberLine, c.emberSoft, 'ui_add'),
      .neutral => (c.ground2, c.line1, c.text2, 'ui_search'),
    };
    final light = Theme.of(context).brightness == .light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon(icon, size: 16, color: toneOf(c, vm.tone)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 4,
              children: [
                Text(
                  vm.message,
                  style: TextStyle(fontSize: 13, color: light ? c.text1 : fg),
                ),
                if (vm.detail case final d?)
                  SelectableText(
                    d,
                    style: mono(size: 12, color: light ? c.text2 : fg),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color toneOf(AppColors c, Tone t) => switch (t) {
    .good => c.good,
    .bad => c.bad,
    .warn => c.warn,
    .ember => c.ember,
    .neutral => c.text3,
  };
}
