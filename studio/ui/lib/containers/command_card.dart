import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What [CommandCard] draws: shell commands the user runs on a host.
final class CommandCardVm extends Equatable {
  const CommandCardVm({
    required this.id,
    required this.title,
    required this.code,
    required this.note,
    required this.copyLabel,
  });

  final String id;
  final String title;

  /// The commands, one per line, exactly as they are copied.
  final String code;
  final String note;

  /// What the copy button does, for assistive technology
  /// (`Copy: Check a copy`).
  final String copyLabel;

  @override
  List<Object?> get props => [id, title, code, note, copyLabel];
}

/// A step done outside Studio, ready to copy: a title, the commands in a
/// code box with a copy button, and a line that says what they do (board
/// `SystemMaint`, *Back up and restore*). Studio runs none of them.
class CommandCard extends StatelessWidget {
  const CommandCard({required this.vm, this.onCopy, super.key});

  final CommandCardVm vm;

  /// The copy button was pressed; the composer puts [CommandCardVm.code] on
  /// the clipboard.
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == .dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.ground0,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Text(
            vm.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: .w600,
              color: c.text1,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                Colors.black.withValues(alpha: dark ? 0.2 : 0.03),
                c.ground0,
              ),
              border: .all(color: c.ground3),
              borderRadius: Radii.control,
            ),
            child: Row(
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                Expanded(
                  // A zero-width space after every character lets a line
                  // break anywhere (the board's `break-all`). It is in the
                  // drawing only: the copy button copies `vm.code`.
                  child: Text(
                    vm.code.split('').join('\u200B'),
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      height: 1.7,
                      color: c.text2,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: vm.copyLabel,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: vm.copyLabel,
                    child: Material(
                      color: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: Radii.segment,
                        side: BorderSide(color: c.line1),
                      ),
                      child: InkWell(
                        onTap: onCopy,
                        borderRadius: Radii.segment,
                        hoverColor: c.text1.withValues(alpha: 0.05),
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: Center(
                            child: AppIcon('ui_copy', size: 14, color: c.text3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            vm.note,
            style: TextStyle(fontSize: 12, height: 1.5, color: c.text4),
          ),
        ],
      ),
    );
  }
}
