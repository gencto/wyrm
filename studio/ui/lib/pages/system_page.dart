import 'package:flutter/material.dart';

import '../buttons/segmented_tabs.dart';
import '../charts/live_sparkline.dart';
import '../containers/detail_inspector.dart';
import '../containers/metric_card.dart';
import '../containers/section_label.dart';
import '../indicators/status_pill.dart';
import '../overlays/log_view.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// Board *Studio · System*: the broker's figures, its message rates, its
/// log; on the right its log level and actions.
class SystemPage extends StatelessWidget {
  const SystemPage({
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.ratesTitle,
    required this.rates,
    required this.rateLabels,
    required this.ratesEmpty,
    required this.logTitle,
    required this.levels,
    required this.level,
    required this.onLevel,
    required this.log,
    required this.logEmpty,
    required this.onAction,
    this.pill,
    this.loadingLog = false,
    this.inspector,
    super.key,
  });

  final String title;
  final String subtitle;
  final StatusPillVm? pill;
  final List<MetricVm> metrics;
  final String ratesTitle;

  /// Messages in and out per second, now.
  final List<double?> rates;
  final List<String> rateLabels;
  final String ratesEmpty;
  final String logTitle;
  final List<TabItemVm> levels;
  final String level;
  final ValueChanged<String> onLevel;
  final List<String> log;
  final String logEmpty;
  final bool loadingLog;
  final DetailInspectorVm? inspector;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: .center,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (pill case final p?) StatusPill(vm: p, dense: true),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 14, color: c.text3)),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final n = (box.maxWidth / 200).floor().clamp(1, 5);
            final w = (box.maxWidth - 12 * (n - 1)) / n;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final m in metrics)
                  SizedBox(
                    width: w,
                    child: MetricCard(vm: m),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.ground1,
            border: .all(color: c.line1),
            borderRadius: Radii.card,
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Text(
                ratesTitle,
                style: const TextStyle(fontSize: 14, fontWeight: .w600),
              ),
              LiveSparkline(
                values: rates,
                labels: rateLabels,
                empty: ratesEmpty,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: SectionLabel(logTitle)),
            SizedBox(
              width: 330,
              child: SegmentedTabs(
                tabs: levels,
                selected: level,
                onSelect: onLevel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 360,
          child: LogView(lines: log, loading: loadingLog, empty: logEmpty),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(child: body),
          if (inspector != null && box.maxWidth >= 1000)
            DetailInspector(vm: inspector!, onAction: onAction),
        ],
      ),
    );
  }
}
