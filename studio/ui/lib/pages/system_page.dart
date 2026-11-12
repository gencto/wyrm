import 'package:equatable/equatable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../alerts/warn_banner.dart';
import '../buttons/button.dart';
import '../buttons/pill_tabs.dart';
import '../charts/traffic_card.dart';
import '../containers/attention_panel.dart';
import '../containers/command_card.dart';
import '../containers/guide_card.dart';
import '../containers/section_card.dart';
import '../containers/standby_pair.dart';
import '../containers/sys_tile.dart';
import '../forms/log_toolbar.dart';
import '../indicators/code_text.dart';
import '../indicators/status_pill.dart';
import '../models/tone.dart';
import '../tables/log_table.dart';
import '../tables/row_list.dart';
import '../tables/term_table.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// A labelled group of tiles on the Overview.
final class TileGroupVm extends Equatable {
  const TileGroupVm({required this.label, required this.tiles});

  final String label;
  final List<SysTileVm> tiles;

  @override
  List<Object?> get props => [label, tiles];
}

/// The Overview tab: every `sys` value as a tile, and the router traffic.
final class SystemOverviewVm extends Equatable {
  const SystemOverviewVm({required this.groups, required this.traffic});

  final List<TileGroupVm> groups;
  final TrafficCardVm traffic;

  @override
  List<Object?> get props => [groups, traffic];
}

/// The Availability tab. With [guide] no standby follows the broker and the
/// tab is that card alone; else the pair, its four values, the banner when
/// the standby is behind, and what the standby holds.
final class SystemAvailVm extends Equatable {
  const SystemAvailVm({
    this.pair,
    this.tiles = const [],
    this.banner,
    this.heldTitle = '',
    this.held = const [],
    this.guide,
  });

  final StandbyPairVm? pair;
  final List<SysTileVm> tiles;
  final WarnBannerVm? banner;
  final String heldTitle;
  final List<TermVm> held;
  final GuideCardVm? guide;

  @override
  List<Object?> get props => [pair, tiles, banner, heldTitle, held, guide];
}

/// The Log tab: the toolbar, the lines, and the broker's own log level.
final class SystemLogVm extends Equatable {
  const SystemLogVm({
    required this.toolbar,
    required this.summary,
    required this.copyLabel,
    required this.saveLabel,
    required this.rows,
    required this.message,
    required this.levelTitle,
    required this.levelKey,
    required this.levelNote,
    required this.levels,
    required this.level,
    this.bad = false,
    this.levelReason,
  });

  final LogToolbarVm toolbar;

  /// `200 lines from the broker's ring · newest first · sys/~act/get_log`;
  /// code between backticks.
  final String summary;
  final String copyLabel;
  final String saveLabel;
  final List<LogRowVm> rows;

  /// What the log box says with no rows, or the broker's refusal.
  final String message;
  final bool bad;
  final String levelTitle;
  final String levelKey;
  final String levelNote;
  final List<PillTabVm> levels;

  /// The level the broker logs at (or the one staged for it).
  final String level;

  /// Why the level cannot be changed; changeable when null.
  final String? levelReason;

  @override
  List<Object?> get props => [
    toolbar,
    summary,
    copyLabel,
    saveLabel,
    rows,
    message,
    bad,
    levelTitle,
    levelKey,
    levelNote,
    levels,
    level,
    levelReason,
  ];
}

/// A link to another workspace.
final class ElsewhereVm extends Equatable {
  const ElsewhereVm({required this.id, required this.label});

  final String id;
  final String label;

  @override
  List<Object?> get props => [id, label];
}

/// The Maintenance tab: the links `clear_conns` would remove, the device
/// profiles, the backup commands.
final class SystemMaintVm extends Equatable {
  const SystemMaintVm({
    required this.staleTitle,
    required this.staleNote,
    required this.stale,
    required this.staleEmpty,
    required this.clearLabel,
    required this.staleFooter,
    required this.profilesTitle,
    required this.profilesNote,
    required this.putLabel,
    required this.profiles,
    required this.profilesEmpty,
    required this.profilesFooter,
    required this.backupTitle,
    required this.backupNote,
    required this.commands,
    required this.backupWarning,
    required this.elsewhereLabel,
    required this.elsewhere,
    this.clearReason,
    this.putReason,
    this.profilesUnlisted = false,
  });

  final String staleTitle;
  final String staleNote;
  final List<RowItemVm> stale;
  final String staleEmpty;
  final String clearLabel;

  /// Why the clear button is disabled (no rights, nothing to clear).
  final String? clearReason;
  final String staleFooter;
  final String profilesTitle;
  final String profilesNote;
  final String putLabel;
  final String? putReason;
  final List<RowItemVm> profiles;
  final String profilesEmpty;

  /// The broker does not list its profiles: [profilesEmpty] is the reason.
  final bool profilesUnlisted;
  final String profilesFooter;
  final String backupTitle;
  final String backupNote;
  final List<CommandCardVm> commands;
  final String backupWarning;
  final String elsewhereLabel;
  final List<ElsewhereVm> elsewhere;

  @override
  List<Object?> get props => [
    staleTitle,
    staleNote,
    stale,
    staleEmpty,
    clearLabel,
    clearReason,
    staleFooter,
    profilesTitle,
    profilesNote,
    putLabel,
    putReason,
    profiles,
    profilesEmpty,
    profilesUnlisted,
    profilesFooter,
    backupTitle,
    backupNote,
    commands,
    backupWarning,
    elsewhereLabel,
    elsewhere,
  ];
}

/// Boards `System`, `SystemAvail`, `SystemAvailLag`, `SystemAvailNone`,
/// `SystemLog`, `SystemMaint` (spec `docs/design/specs/system.md`): the
/// broker's own page. A title row with the four tabs, the selected tab in
/// the main column, and the attention panel on the right of every tab
/// (under the main column below 1100 px).
///
/// It shows what the broker serves under `sys`; it is handed finished
/// values and decides nothing.
class SystemPage extends StatelessWidget {
  const SystemPage({
    required this.title,
    required this.meta,
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.overview,
    required this.availability,
    required this.log,
    required this.maintenance,
    required this.attention,
    required this.onAttention,
    required this.onTile,
    required this.onMeasure,
    required this.onSource,
    required this.onLevel,
    required this.onFilter,
    required this.onLines,
    required this.onAround,
    required this.onAuto,
    required this.onGetLog,
    required this.onCopyLog,
    required this.onSaveLog,
    required this.onLogLevel,
    required this.onClear,
    required this.onPutProfile,
    required this.onRemoveProfile,
    required this.onCopyCommand,
    required this.onElsewhere,
    this.pill,
    this.tabsLabel,
    this.stale = false,
    this.onBanner,
    this.onGuide,
    this.onTrafficWindow,
    this.onTrafficFollow,
    this.onTrafficReset,
    super.key,
  });

  /// The tab ids, in the order of the bar.
  static const overviewTab = 'overview';
  static const availabilityTab = 'availability';
  static const logTab = 'log';
  static const maintenanceTab = 'maintenance';

  final String title;
  final StatusPillVm? pill;

  /// `0.1.0 · Zenoh 1.10.1 · rust (prod) · started … · up 6 d 4 h`.
  final String meta;
  final List<PillTabVm> tabs;
  final String? tabsLabel;
  final String tab;
  final ValueChanged<String> onTab;

  /// The broker does not answer: the values are the last known, greyed.
  final bool stale;

  final SystemOverviewVm overview;
  final SystemAvailVm availability;
  final SystemLogVm log;
  final SystemMaintVm maintenance;
  final AttentionPanelVm attention;

  final ValueChanged<String> onAttention;

  /// A tile with a destination was tapped; its key under `sys`.
  final ValueChanged<String> onTile;
  final ValueChanged<String> onMeasure;

  /// The traffic trend's window (µs), `Follow now` and `Reset zoom`.
  final void Function(int start, int end)? onTrafficWindow;
  final VoidCallback? onTrafficFollow;
  final VoidCallback? onTrafficReset;
  final VoidCallback? onBanner;
  final VoidCallback? onGuide;
  final ValueChanged<String> onSource;
  final ValueChanged<String> onLevel;
  final ValueChanged<String> onFilter;
  final ValueChanged<int> onLines;

  /// The Log toolbar's time: `hh:mm:ss`, or empty when it was cleared.
  final ValueChanged<String> onAround;
  final ValueChanged<bool> onAuto;
  final VoidCallback onGetLog;
  final VoidCallback onCopyLog;
  final VoidCallback onSaveLog;
  final ValueChanged<String> onLogLevel;
  final VoidCallback onClear;
  final VoidCallback onPutProfile;
  final ValueChanged<String> onRemoveProfile;
  final ValueChanged<String> onCopyCommand;
  final ValueChanged<String> onElsewhere;

  static const _shield = '''
<svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2"
  stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>
</svg>''';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 1100;
      final body = switch (tab) {
        availabilityTab => _availability(context),
        logTab => _log(context),
        maintenanceTab => _maintenance(context),
        _ => _overview(context),
      };
      final main = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 24,
          children: [
            _header(context),
            if (stale) Opacity(opacity: 0.55, child: body) else body,
          ],
        ),
      );
      // The boards' text has the fonts' own line height (1.3 for both IBM
      // Plex families) wherever they name none.
      final Widget page;
      if (!wide) {
        page = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              main,
              AttentionPanel(vm: attention, onItem: onAttention, fill: false),
            ],
          ),
        );
      } else {
        // The main column takes what the panel leaves (the board's flex
        // 999 to 1: the panel stays near 300 and never passes 340). The
        // page scrolls as one: the panel is as tall as the main column, at
        // least the window, with the broker's facts at its foot.
        final side = (300 + (box.maxWidth - 860) / 1000).clamp(300.0, 340.0);
        page = SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(right: side),
                  child: main,
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: side,
                  child: AttentionPanel(vm: attention, onItem: onAttention),
                ),
              ],
            ),
          ),
        );
      }
      return DefaultTextStyle.merge(
        style: const TextStyle(height: 1.3),
        child: page,
      );
    },
  );

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Wrap(
      alignment: .spaceBetween,
      crossAxisAlignment: .end,
      spacing: 16,
      runSpacing: 16,
      children: [
        Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          spacing: 6,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: .center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: .w600,
                    letterSpacing: -0.26,
                    color: c.text1,
                  ),
                ),
                if (pill case final p?) _pill(c, p),
              ],
            ),
            Text(meta, style: TextStyle(fontSize: 14, color: c.text3)),
          ],
        ),
        PillTabs(
          tabs: tabs,
          selected: tab,
          onSelect: onTab,
          label: tabsLabel,
        ),
      ],
    );
  }

  /// The board's pill: 24 px high, between the dense and the plain
  /// `StatusPill`.
  Widget _pill(AppColors c, StatusPillVm p) {
    final (fg, bg) = switch (p.tone) {
      .good => (c.good, c.goodTint),
      .warn => (c.warn, c.warnTint),
      .bad => (c.bad, c.badTint),
      .ember => (c.emberSoft, c.emberTint),
      .neutral => (c.text3, c.ground4),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: Radii.pill),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: .circle),
          ),
          Text(
            p.label,
            style: TextStyle(fontSize: 12, fontWeight: .w500, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _groupLabel(AppColors c, String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 12,
      fontWeight: .w600,
      letterSpacing: 0.72,
      color: c.text4,
    ),
  );

  Widget _overview(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 24,
      children: [
        for (final g in overview.groups)
          Column(
            crossAxisAlignment: .stretch,
            spacing: 10,
            children: [
              _groupLabel(c, g.label),
              SysTileGrid(tiles: g.tiles, onTile: onTile),
            ],
          ),
        TrafficCard(
          vm: overview.traffic,
          onMeasure: onMeasure,
          onWindow: onTrafficWindow,
          onFollow: onTrafficFollow,
          onReset: onTrafficReset,
        ),
      ],
    );
  }

  Widget _availability(BuildContext context) {
    final c = context.colors;
    final a = availability;
    if (a.guide case final g?) {
      return Align(
        alignment: Alignment.topLeft,
        child: GuideCard(vm: g, onLink: onGuide),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 20,
      children: [
        if (a.pair case final p?) StandbyPair(vm: p),
        SysTileGrid(tiles: a.tiles, minWidth: 200, relaxed: true),
        if (a.banner case final b?) WarnBanner(vm: b, onAction: onBanner),
        Column(
          crossAxisAlignment: .stretch,
          spacing: 10,
          children: [
            _groupLabel(c, a.heldTitle),
            TermTable(rows: a.held),
          ],
        ),
      ],
    );
  }

  Widget _log(BuildContext context) {
    final c = context.colors;
    final l = log;
    final export = l.rows.isNotEmpty && !l.bad;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        LogToolbar(
          vm: l.toolbar,
          onSource: onSource,
          onLevel: onLevel,
          onFilter: onFilter,
          onLines: onLines,
          onAround: onAround,
          onAuto: onAuto,
          onGet: onGetLog,
        ),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: CodeText(
                l.summary,
                maxLines: 2,
                style: TextStyle(fontSize: 12, color: c.text4),
              ),
            ),
            Button.quiet(
              label: l.copyLabel,
              onPressed: export ? onCopyLog : null,
              size: ButtonSize.small,
              fontSize: 12,
              fontWeight: .w400,
            ),
            Button.quiet(
              label: l.saveLabel,
              onPressed: export ? onSaveLog : null,
              size: ButtonSize.small,
              fontSize: 12,
              fontWeight: .w400,
            ),
          ],
        ),
        LogTable(rows: l.rows, message: l.message, bad: l.bad),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.ground1,
            border: .all(color: c.line1),
            borderRadius: Radii.card,
          ),
          child: _beside(
            minLeft: 260,
            right: 320,
            left: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              spacing: 4,
              children: [
                Text.rich(
                  TextSpan(
                    text: '${l.levelTitle} ',
                    children: [
                      TextSpan(
                        text: l.levelKey,
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          fontWeight: .w400,
                          color: c.text4,
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: .w600,
                    color: c.text1,
                  ),
                ),
                CodeText(
                  l.levelNote,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: c.text4,
                  ),
                ),
              ],
            ),
            child: PillTabs(
              tabs: l.levels,
              selected: l.level,
              onSelect: onLogLevel,
              label: l.levelTitle,
              height: 32,
              fontSize: 12,
              inset: true,
              equal: true,
              mono: true,
              disabledReason: l.levelReason,
            ),
          ),
        ),
      ],
    );
  }

  /// [left] takes the room beside [child], which is [right] wide; when
  /// less than [minLeft] would be left, [child] goes under it.
  Widget _beside({
    required Widget left,
    required Widget child,
    required double minLeft,
    required double right,
  }) => LayoutBuilder(
    builder: (context, box) => box.maxWidth >= minLeft + 20 + right
        ? Row(
            spacing: 20,
            children: [
              Expanded(child: left),
              SizedBox(width: right, child: child),
            ],
          )
        : Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [left, child],
          ),
  );

  Widget _maintenance(BuildContext context) {
    final c = context.colors;
    final m = maintenance;
    final stale = SectionCard(
      title: m.staleTitle,
      description: m.staleNote,
      footer: m.staleFooter,
      child: Column(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          SizedBox(
            width: double.infinity,
            child: RowList(rows: m.stale, empty: m.staleEmpty),
          ),
          Button.danger(
            label: m.clearLabel,
            onPressed: m.clearReason == null ? onClear : null,
            disabledReason: m.clearReason,
            fontWeight: .w400,
          ),
        ],
      ),
    );
    final profiles = SectionCard(
      title: m.profilesTitle,
      description: m.profilesNote,
      footer: m.profilesFooter,
      trailing: Button.secondary(
        label: m.putLabel,
        onPressed: m.putReason == null ? onPutProfile : null,
        disabledReason: m.putReason,
        size: ButtonSize.compact,
        fontSize: 13,
        fontWeight: .w400,
      ),
      child: RowList(
        rows: m.profiles,
        empty: m.profilesEmpty,
        emptyBad: m.profilesUnlisted,
        onAction: onRemoveProfile,
      ),
    );
    final backup = SectionCard(
      title: m.backupTitle,
      description: m.backupNote,
      descriptionWidth: 860,
      gap: 14,
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final n = ((box.maxWidth + 12) / 312).floor().clamp(
                1,
                m.commands.isEmpty ? 1 : m.commands.length,
              );
              return Column(
                spacing: 12,
                children: [
                  for (var i = 0; i < m.commands.length; i += n)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: .stretch,
                        spacing: 12,
                        children: [
                          for (var j = i; j < i + n; j++)
                            Expanded(
                              child: j < m.commands.length
                                  ? CommandCard(
                                      vm: m.commands[j],
                                      onCopy: () =>
                                          onCopyCommand(m.commands[j].id),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          Row(
            crossAxisAlignment: .start,
            spacing: 10,
            children: [
              SvgPicture.string(
                _shield,
                width: 16,
                height: 16,
                colorFilter: ColorFilter.mode(c.warn, BlendMode.srcIn),
              ),
              Expanded(
                child: Text(
                  m.backupWarning,
                  style: TextStyle(fontSize: 12, height: 1.5, color: c.warn),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          if (box.maxWidth >= 856)
            Row(
              crossAxisAlignment: .start,
              spacing: 16,
              children: [
                Expanded(child: stale),
                Expanded(child: profiles),
              ],
            )
          else ...[
            stale,
            profiles,
          ],
          backup,
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              Text(
                m.elsewhereLabel,
                style: TextStyle(fontSize: 13, color: c.text4),
              ),
              for (final e in m.elsewhere)
                InkWell(
                  onTap: () => onElsewhere(e.id),
                  child: Text(
                    e.label,
                    style: TextStyle(fontSize: 13, color: c.text2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dot of the Availability tab: amber while the standby is behind or a
/// fork was moved aside, grey with no standby, none when all is well.
Tone? availabilityDot({required bool standby, required bool behind}) =>
    !standby ? Tone.neutral : (behind ? Tone.warn : null);
