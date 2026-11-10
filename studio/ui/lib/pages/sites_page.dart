import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../charts/site_map.dart';
import '../containers/detail_inspector.dart';
import '../containers/page_header.dart';
import '../forms/action_form.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// Board *Studio · Sites* (and its shapes Chain, Star, Two upstreams): a
/// header with Connect to an upstream and Token for a site below, the
/// waiting banner, the map with its legend, and the inspector of the
/// selected node.
class SitesPage extends StatelessWidget {
  const SitesPage({
    required this.title,
    required this.subtitle,
    required this.connectLabel,
    required this.tokenLabel,
    required this.legend,
    required this.nodes,
    required this.onNode,
    required this.onConnect,
    required this.onToken,
    required this.onAction,
    this.connectReason,
    this.waiting,
    this.reviewLabel = 'Review',
    this.onReview,
    this.inspector,
    this.onSubmit,
    this.onSecondary,
    this.busy = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final String connectLabel;
  final String tokenLabel;

  /// Why the user cannot connect or issue tokens (needs config on sys).
  final String? connectReason;
  final (String, String, String, String) legend;
  final List<SiteNodeVm> nodes;
  final ValueChanged<String> onNode;
  final VoidCallback onConnect;
  final VoidCallback onToken;

  /// `2 waiting to be let in: …`, or null.
  final String? waiting;
  final String reviewLabel;
  final VoidCallback? onReview;
  final DetailInspectorVm? inspector;
  final ValueChanged<String> onAction;
  final FormSubmit? onSubmit;
  final VoidCallback? onSecondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        PageHeader(
          title: title,
          subtitle: subtitle,
          trailing: Button.secondary(
            label: connectLabel,
            icon: 'action_up',
            disabledReason: connectReason,
            onPressed: connectReason == null ? onConnect : null,
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: .centerLeft,
          child: Button.secondary(
            label: tokenLabel,
            icon: 'action_key',
            disabledReason: connectReason,
            onPressed: connectReason == null ? onToken : null,
          ),
        ),
        if (waiting case final w?) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.warnTint,
              border: .all(color: c.warnLine),
              borderRadius: Radii.control,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    w,
                    style: TextStyle(fontSize: 14, color: c.text1),
                  ),
                ),
                if (onReview != null)
                  TextButton(
                    onPressed: onReview,
                    child: Text(
                      reviewLabel,
                      style: TextStyle(color: c.emberSoft),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.ground0,
            border: .all(color: c.line1),
            borderRadius: Radii.panel,
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 18,
            children: [
              SiteLegend(labels: legend),
              SiteMap(nodes: nodes, onTap: onNode),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final ins = inspector;
        if (ins == null || box.maxWidth < 1000) {
          return body;
        }
        return Row(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(child: body),
            DetailInspector(
              vm: ins,
              onAction: onAction,
              onSubmit: onSubmit,
              onSecondary: onSecondary,
              busy: busy,
            ),
          ],
        );
      },
    );
  }
}
