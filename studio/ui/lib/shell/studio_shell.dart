import 'package:flutter/material.dart';

import '../alerts/offline_banner.dart';
import '../theme/extensions/colors.dart';
import 'top_bar.dart';
import 'workspace_rail.dart';

/// The four fixed zones (board *Design system* §01): top bar 56, rail 76,
/// and the workspace [child] (tree, workspace and inspector are the tab's
/// own). Below 800 px the rail becomes a bottom bar.
class StudioShell extends StatelessWidget {
  const StudioShell({
    required this.topBar,
    required this.rail,
    required this.selected,
    required this.onSelect,
    required this.child,
    this.offline,
    this.more = 'More',
    super.key,
  });

  /// The top bar, built with the shell's width in mind.
  final TopBar Function(bool compact) topBar;
  final List<RailItemVm> rail;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget child;

  /// The offline banner's text, or null while connected.
  final String? offline;
  final String more;

  /// Narrower than this, the rail moves to the bottom.
  static const breakpoint = 800.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < breakpoint;
      return Scaffold(
        backgroundColor: context.colors.ground0,
        body: SafeArea(
          child: Column(
            children: [
              topBar(compact),
              if (offline case final m?) OfflineBanner(message: m),
              Expanded(
                child: compact
                    ? child
                    : Row(
                        crossAxisAlignment: .stretch,
                        children: [
                          WorkspaceRail(
                            items: rail,
                            selected: selected,
                            onSelect: onSelect,
                          ),
                          Expanded(child: child),
                        ],
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: compact
            ? WorkspaceBottomBar(
                items: rail,
                selected: selected,
                onSelect: onSelect,
                more: more,
              )
            : null,
      );
    },
  );
}
