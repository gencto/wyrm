import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// One entry of a project's menu: a page, or a group of pages.
final class ViewNavItemVm extends Equatable {
  const ViewNavItemVm({
    required this.id,
    required this.label,
    this.selected = false,
    this.badge = 0,
    this.badgeState = ViewState.alarm,
    this.children = const [],
  });

  /// What [ViewProjectShell.onItem] reports (`page` or
  /// `page?param=key`); empty for a group.
  final String id;
  final String label;
  final bool selected;

  /// Active alarms under the keys the page reads; 0 draws no badge.
  final int badge;

  /// The worst of them: the badge's colour.
  final ViewState badgeState;
  final List<ViewNavItemVm> children;

  @override
  List<Object?> get props => [id, label, selected, badge, badgeState, children];
}

/// What [ViewProjectShell] draws around a page.
final class ViewProjectVm extends Equatable {
  const ViewProjectVm({
    required this.title,
    required this.items,
    required this.crumbs,
    this.clock = '',
    this.alarms = 0,
    this.alarmText = '',
    this.rotation = 0,
    this.rotationAt = 0,
  });

  final String title;
  final List<ViewNavItemVm> items;

  /// `Overview › BACnet devices › d1`: the back stack, the last is the
  /// page shown.
  final List<String> crumbs;
  final String clock;

  /// Unacknowledged alarms: the banner is drawn above the page when > 0.
  final int alarms;
  final String alarmText;

  /// The pages a kiosk rotates through, and the one shown (its dots).
  final int rotation;
  final int rotationAt;

  @override
  List<Object?> get props => [
    title,
    items,
    crumbs,
    clock,
    alarms,
    alarmText,
    rotation,
    rotationAt,
  ];
}

/// The frame and the menu of a view project
/// (docs/design/specs/genui-views.md §3.3, boards `GenProject*`) around
/// one page ([child], a `ViewSurface`). The menu changes form by the
/// density of where it is shown: a sidebar with groups on a desktop, a row
/// of tabs 52 high on a panel, a bottom bar of five with *More* on a
/// phone, none on a kiosk (rotation dots instead).
class ViewProjectShell extends StatelessWidget {
  const ViewProjectShell({
    required this.vm,
    required this.density,
    required this.child,
    required this.onItem,
    required this.onCrumb,
    this.onBack,
    this.onAcknowledge,
    super.key,
  });

  final ViewProjectVm vm;
  final ViewDensity density;
  final Widget child;
  final ValueChanged<String> onItem;

  /// A tap on a breadcrumb before the last, by its index.
  final ValueChanged<int> onCrumb;

  /// Null on the first page of the stack.
  final VoidCallback? onBack;
  final VoidCallback? onAcknowledge;

  /// The pages of the menu in one row: a group gives its pages.
  List<ViewNavItemVm> get _flat => [
    for (final i in vm.items)
      if (i.children.isEmpty) i else ...i.children,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = density;
    final page = Column(
      crossAxisAlignment: .stretch,
      children: [
        _Header(vm: vm, density: d),
        if (d == .panel) _Tabs(items: _flat, onItem: onItem),
        if (vm.alarms > 0)
          _Banner(vm: vm, density: d, onAcknowledge: onAcknowledge),
        if (vm.crumbs.length > 1)
          _Crumbs(
            crumbs: vm.crumbs,
            density: d,
            onCrumb: onCrumb,
            onBack: onBack,
          ),
        Expanded(child: child),
        if (d == .phone) _BottomBar(items: _flat, onItem: onItem),
        if (d == .kiosk && vm.rotation > 1)
          _Dots(count: vm.rotation, at: vm.rotationAt),
      ],
    );
    return ColoredBox(
      color: c.ground0,
      child: d == .desktop
          ? Row(
              crossAxisAlignment: .stretch,
              children: [
                _Sidebar(items: vm.items, onItem: onItem),
                Expanded(child: page),
              ],
            )
          : page,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vm, required this.density});

  final ViewProjectVm vm;
  final ViewDensity density;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: density.header,
      padding: EdgeInsets.symmetric(horizontal: density.pad),
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(bottom: BorderSide(color: c.line1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              vm.title,
              maxLines: 1,
              overflow: .ellipsis,
              style: boardText(
                size: density.label + 5,
                weight: .w600,
                color: c.text1,
              ),
            ),
          ),
          Text(
            vm.clock,
            style: boardText(
              size: density.label + 1,
              color: c.text3,
              code: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.vm, required this.density, this.onAcknowledge});

  final ViewProjectVm vm;
  final ViewDensity density;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: density.pad, vertical: 8),
      decoration: BoxDecoration(
        color: c.badTint,
        border: Border(bottom: BorderSide(color: c.badLine)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Text(
            S.current.viewsAlarmsActive(vm.alarms),
            style: boardText(
              size: density.label,
              weight: .w600,
              color: c.badText,
            ),
          ),
          Expanded(
            child: Text(
              vm.alarmText,
              maxLines: 1,
              overflow: .ellipsis,
              style: boardText(size: density.label, color: c.badText),
            ),
          ),
          SizedBox(
            height: density.button,
            child: Button.danger(
              label: S.current.viewsAcknowledge,
              onPressed: onAcknowledge,
              fontSize: density.label,
            ),
          ),
        ],
      ),
    );
  }
}

class _Crumbs extends StatelessWidget {
  const _Crumbs({
    required this.crumbs,
    required this.density,
    required this.onCrumb,
    this.onBack,
  });

  final List<String> crumbs;
  final ViewDensity density;
  final ValueChanged<int> onCrumb;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = boardText(size: density.label, color: c.text3);
    return Padding(
      padding: EdgeInsets.fromLTRB(density.pad, 8, density.pad, 0),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            height: density == .desktop ? 32 : density.button,
            child: Button.quiet(
              label: S.current.viewsBack,
              onPressed: onBack,
              fontSize: density.label,
              inset: 12,
            ),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: .center,
              spacing: 6,
              children: [
                for (final (i, crumb) in crumbs.indexed) ...[
                  if (i > 0) Text('›', style: style.copyWith(color: c.text4)),
                  if (i < crumbs.length - 1)
                    InkWell(
                      onTap: () => onCrumb(i),
                      child: Text(crumb, style: style),
                    )
                  else
                    Text(
                      crumb,
                      style: style.copyWith(
                        color: c.text1,
                        fontWeight: .w500,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.item);

  final ViewNavItemVm item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: .center,
      decoration: BoxDecoration(
        color: item.badgeState == .warn ? c.warnTint : c.badTint,
        borderRadius: Radii.pill,
      ),
      child: Text(
        '${item.badge}',
        style: boardText(
          size: 12,
          weight: .w600,
          color: item.badgeState == .warn ? c.warn : c.badText,
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.onItem});

  final List<ViewNavItemVm> items;
  final ValueChanged<String> onItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(ViewNavItemVm i, {bool nested = false}) => Material(
      color: i.selected ? c.emberTint : Colors.transparent,
      borderRadius: Radii.segment,
      child: InkWell(
        borderRadius: Radii.segment,
        onTap: () => onItem(i.id),
        child: Container(
          height: 36,
          padding: EdgeInsets.only(left: nested ? 22 : 10, right: 8),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  i.label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: boardText(
                    size: 13,
                    weight: i.selected ? .w600 : .w400,
                    color: i.selected ? c.emberSoft : c.text2,
                  ),
                ),
              ),
              if (i.badge > 0) _Badge(i),
            ],
          ),
        ),
      ),
    );
    return Container(
      width: 208,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(right: BorderSide(color: c.line1)),
      ),
      child: ListView(
        children: [
          for (final i in items)
            if (i.children.isEmpty && i.id.isNotEmpty)
              row(i)
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 8, 4),
                child: Text(
                  i.label.toUpperCase(),
                  style: boardText(
                    size: 11,
                    weight: .w600,
                    color: c.text4,
                    tracking: 0.66,
                  ),
                ),
              ),
              for (final child in i.children) row(child, nested: true),
            ],
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.items, required this.onItem});

  final List<ViewNavItemVm> items;
  final ValueChanged<String> onItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: ViewDensity.tabs,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(bottom: BorderSide(color: c.line1)),
      ),
      child: ListView(
        scrollDirection: .horizontal,
        children: [
          for (final i in items)
            InkWell(
              onTap: () => onItem(i.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: i.selected ? c.ember : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    Text(
                      i.label,
                      style: boardText(
                        size: 16,
                        weight: i.selected ? .w600 : .w400,
                        color: i.selected ? c.text1 : c.text3,
                      ),
                    ),
                    if (i.badge > 0) _Badge(i),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.items, required this.onItem});

  final List<ViewNavItemVm> items;
  final ValueChanged<String> onItem;

  /// Five places: five pages, or four and *More*.
  static const places = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = items.length <= places ? items : items.sublist(0, places - 1);
    final rest = items.length <= places
        ? const <ViewNavItemVm>[]
        : items.sublist(places - 1);
    Widget place(
      String label, {
      required VoidCallback onTap,
      bool selected = false,
      ViewNavItemVm? badge,
    }) => Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: .center,
          spacing: 4,
          children: [
            if (badge != null && badge.badge > 0)
              _Badge(badge)
            else
              Container(
                width: 18,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? c.ember : Colors.transparent,
                  borderRadius: Radii.pill,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: .ellipsis,
                style: boardText(
                  size: 12,
                  weight: selected ? .w600 : .w400,
                  color: selected ? c.text1 : c.text3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Row(
        children: [
          for (final i in shown)
            place(
              i.label,
              onTap: () => onItem(i.id),
              selected: i.selected,
              badge: i,
            ),
          if (rest.isNotEmpty)
            place(
              S.current.viewsMore,
              selected: rest.any((i) => i.selected),
              onTap: () async {
                final id = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: c.ground1,
                  builder: (context) => ListView(
                    shrinkWrap: true,
                    children: [
                      for (final i in rest)
                        InkWell(
                          onTap: () => Navigator.of(context).pop(i.id),
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              spacing: 8,
                              children: [
                                Expanded(
                                  child: Text(
                                    i.label,
                                    style: boardText(size: 15, color: c.text1),
                                  ),
                                ),
                                if (i.badge > 0) _Badge(i),
                                if (i.selected)
                                  AppIcon('ui_check', size: 16, color: c.ember),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
                if (id != null) {
                  onItem(id);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.at});

  final int count;
  final int at;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: .center,
        spacing: 8,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: .circle,
                color: i == at ? c.ember : c.line3,
              ),
            ),
        ],
      ),
    );
  }
}
