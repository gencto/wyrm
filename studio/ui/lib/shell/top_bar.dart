import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'wyrm_logo.dart';

/// A site of the switcher.
final class SiteItemVm extends Equatable {
  const SiteItemVm({required this.site, this.detail, this.current = false});

  final String site;

  /// `this broker`, `via edge`, `upstream`.
  final String? detail;
  final bool current;

  @override
  List<Object?> get props => [site, detail, current];
}

/// What the top bar shows.
final class TopBarVm extends Equatable {
  const TopBarVm({
    required this.site,
    required this.sites,
    required this.connected,
    required this.changes,
    required this.user,
    required this.role,
    this.siteDetail,
    this.reviewReason,
  });

  /// The site on screen.
  final String site;

  /// `via edge · central`: how it is reached.
  final String? siteDetail;
  final List<SiteItemVm> sites;
  final bool connected;

  /// Staged changes waiting for Review and apply.
  final int changes;

  /// Why Review and apply is disabled (nothing staged).
  final String? reviewReason;
  final String user;
  final String role;

  @override
  List<Object?> get props => [
    site,
    siteDetail,
    sites,
    connected,
    changes,
    reviewReason,
    user,
    role,
  ];
}

/// Board *Studio · Explorer* top bar: logo, site switcher, search (⌘K),
/// Review and apply with the staged count, account.
class TopBar extends StatelessWidget {
  const TopBar({
    required this.vm,
    required this.onSite,
    required this.onSearch,
    required this.onReview,
    required this.onLogOut,
    this.compact = false,
    this.labels = const TopBarLabels(),
    super.key,
  });

  final TopBarVm vm;
  final ValueChanged<String> onSite;
  final VoidCallback onSearch;
  final VoidCallback onReview;
  final VoidCallback onLogOut;

  /// Below 800 px: no search field (the icon opens it), no wordmark text.
  final bool compact;
  final TopBarLabels labels;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.ground0,
        border: Border(bottom: BorderSide(color: c.line1)),
      ),
      child: Row(
        spacing: compact ? 10 : 20,
        children: [
          WyrmLogo(showStudio: !compact),
          // Site names and the route are user text: the switcher gives
          // way before the buttons do.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: _SiteSwitcher(vm: vm, onSite: onSite, compact: compact),
          ),
          if (!compact)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _SearchBox(onTap: onSearch, hint: labels.search),
              ),
            ),
          const Spacer(),
          if (compact)
            IconButton(
              onPressed: onSearch,
              icon: AppIcon('ui_search', color: c.text3),
            ),
          _ReviewButton(
            count: vm.changes,
            label: compact ? labels.reviewShort : labels.review,
            reason: vm.reviewReason,
            onTap: onReview,
          ),
          _Account(vm: vm, onLogOut: onLogOut, logOut: labels.logOut),
        ],
      ),
    );
  }
}

/// The words of the top bar, localized by the connector.
final class TopBarLabels {
  const TopBarLabels({
    this.search = 'Go to a node, action or link',
    this.review = 'Review and apply',
    this.reviewShort = 'Review',
    this.logOut = 'Log out',
  });

  final String search;
  final String review;
  final String reviewShort;
  final String logOut;
}

class _SiteSwitcher extends StatelessWidget {
  const _SiteSwitcher({
    required this.vm,
    required this.onSite,
    required this.compact,
  });

  final TopBarVm vm;
  final ValueChanged<String> onSite;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<String>(
      tooltip: '',
      onSelected: onSite,
      color: c.ground2,
      position: .under,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.control,
        side: BorderSide(color: c.line2),
      ),
      itemBuilder: (_) => [
        for (final s in vm.sites)
          PopupMenuItem(
            value: s.site,
            child: Row(
              spacing: 10,
              children: [
                Text(
                  s.site,
                  style: mono(
                    weight: s.current ? .w600 : .w400,
                    color: s.current ? c.text1 : c.text2,
                  ),
                ),
                if (s.detail case final d?)
                  Text(d, style: TextStyle(fontSize: 12, color: c.text4)),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.ground2,
          border: .all(color: c.line2),
          borderRadius: Radii.control,
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: 10,
          children: [
            StateMark(
              mark: vm.connected ? Mark.dot : Mark.ring,
              color: vm.connected ? c.good : c.warn,
            ),
            Flexible(
              child: Text(
                vm.site,
                maxLines: 1,
                overflow: .ellipsis,
                style: mono(size: 14, color: c.text1),
              ),
            ),
            if (!compact && vm.siteDetail != null)
              Flexible(
                child: Text(
                  vm.siteDetail!,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: 12, color: c.text4),
                ),
              ),
            AppIcon('ui_chevron_down', size: 16, color: c.text3),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap, required this.hint});

  final VoidCallback onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.control,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.ground2,
          border: .all(color: c.line1),
          borderRadius: Radii.control,
        ),
        // A narrow box drops the key cap, then the hint, never overflows.
        child: LayoutBuilder(
          builder: (context, box) => Row(
            spacing: 10,
            children: [
              AppIcon('ui_search', size: 16, color: c.text3),
              if (box.maxWidth >= 60)
                Expanded(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 14, color: c.text4),
                  ),
                ),
              if (box.maxWidth >= 140)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: .all(color: c.line2),
                    borderRadius: Radii.chip,
                  ),
                  child: Text('⌘K', style: mono(size: 12, color: c.text3)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({
    required this.count,
    required this.label,
    required this.reason,
    required this.onTap,
  });

  final int count;
  final String label;
  final String? reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = count > 0;
    final button = Material(
      color: enabled ? c.ember : c.ground2,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.button,
        side: BorderSide(color: enabled ? c.ember : c.line1),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: Radii.button,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            spacing: 10,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: .w600,
                  color: enabled ? c.onEmber : c.muted,
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: .center,
                decoration: BoxDecoration(
                  color: enabled ? c.ground0 : c.ground4,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled ? c.emberSoft : c.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return enabled || reason == null
        ? button
        : Tooltip(message: reason, child: button);
  }
}

class _Account extends StatelessWidget {
  const _Account({
    required this.vm,
    required this.onLogOut,
    required this.logOut,
  });

  final TopBarVm vm;
  final VoidCallback onLogOut;
  final String logOut;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initials = vm.user.isEmpty
        ? '?'
        : vm.user
              .replaceFirst(RegExp('^user:'), '')
              .characters
              .take(2)
              .toString()
              .toUpperCase();
    return PopupMenuButton<String>(
      tooltip: '${vm.user}, ${vm.role}',
      color: c.ground2,
      position: .under,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.control,
        side: BorderSide(color: c.line2),
      ),
      onSelected: (_) => onLogOut(),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(vm.user, style: mono(color: c.text1)),
              Text(vm.role, style: TextStyle(fontSize: 12, color: c.text3)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Text(logOut, style: TextStyle(fontSize: 14, color: c.text1)),
        ),
      ],
      child: Container(
        width: 40,
        height: 40,
        alignment: .center,
        decoration: BoxDecoration(
          shape: .circle,
          color: c.ground4,
          border: .all(color: c.line2),
        ),
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 13,
            fontWeight: .w600,
            color: c.text1,
          ),
        ),
      ),
    );
  }
}
