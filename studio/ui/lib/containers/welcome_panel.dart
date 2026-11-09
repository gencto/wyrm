import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../indicators/app_icon.dart';
import '../indicators/login_steps.dart';
import '../indicators/sweep_bar.dart';
import '../indicators/wyrm_loader.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What the welcome says while the tree opens (docs/design/specs/login.md
/// §5), every part already resolved.
final class WelcomePanelVm extends Equatable {
  const WelcomePanelVm({
    required this.title,
    required this.site,
    this.facts = const [],
    this.steps = const [],
    this.step = 0,
    this.late = const {},
  });

  /// `Welcome, olena`.
  final String title;

  /// The site whose tree opens, shown in mono in `Opening the tree of …`.
  final String site;

  /// The lines from `me()` and the first list, each ticked in teal; only the
  /// parts known (`engineer on plant · reaches edge and central`,
  /// `14 links`).
  final List<String> facts;

  /// What is read before Studio opens, resolved (`Reading the flows`, …),
  /// shown as [LoginSteps]; empty hides the list.
  final List<String> steps;

  /// The step running, 0-based; `steps.length` when all are done.
  final int step;

  /// The steps that did not finish in time (they go on in the background).
  final Set<int> late;

  @override
  List<Object?> get props => [title, site, facts, steps, step, late];
}

/// The welcome in place of the form: the large crawl loader, the greeting,
/// `Opening the tree of <site>…`, the bar in a 260 × 4 track, the preload's
/// steps and what is known so far — a column centred, 26 apart, 40 above and
/// below.
class WelcomePanel extends StatelessWidget {
  const WelcomePanel({required this.vm, super.key});

  final WelcomePanelVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final opening = S.current.openingTreeOf(vm.site);
    final at = opening.indexOf(vm.site);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: .min,
        spacing: 26,
        children: [
          WyrmLoader(
            size: .large,
            label: S.current.openingTree,
          ),
          Column(
            spacing: 8,
            children: [
              Text(
                vm.title,
                textAlign: .center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: .w600,
                  color: c.text1,
                ),
              ),
              Text.rich(
                TextSpan(
                  children: at < 0
                      ? [TextSpan(text: opening)]
                      : [
                          TextSpan(text: opening.substring(0, at)),
                          TextSpan(
                            text: vm.site,
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              color: c.text1,
                            ),
                          ),
                          TextSpan(
                            text: opening.substring(at + vm.site.length),
                          ),
                        ],
                ),
                textAlign: .center,
                style: TextStyle(fontSize: 14, color: c.text3),
              ),
            ],
          ),
          SweepBar.track(color: c.ember, track: c.ground3),
          if (vm.steps.isNotEmpty)
            // A left-aligned list, centred as a block under the bar.
            IntrinsicWidth(
              child: LoginSteps(
                steps: vm.steps,
                current: vm.step,
                late: vm.late,
              ),
            ),
          if (vm.facts.isNotEmpty)
            Column(
              spacing: 6,
              children: [
                for (final f in vm.facts)
                  Row(
                    mainAxisSize: .min,
                    spacing: 4,
                    children: [
                      AppIcon('ui_check', size: 16, color: c.good),
                      Flexible(
                        child: Text(
                          f,
                          textAlign: .center,
                          style: TextStyle(fontSize: 13, color: c.text4),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
