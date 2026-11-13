import 'dart:convert';

import '../keys.dart';

/// One page of a view project (docs/design/specs/genui-views.md §3.3).
final class ViewPageDef {
  const ViewPageDef({
    required this.id,
    required this.title,
    required this.doc,
    this.params = const {},
  });

  final String id;

  /// May carry a parameter: `Device {device}`.
  final String title;

  /// The file of the page's A2UI document.
  final String doc;

  /// Parameter name → the node its value is a child of.
  final Map<String, String> params;

  /// The title with each parameter replaced by the last segment of its
  /// value.
  String titleFor(Map<String, String> values) {
    var out = title;
    for (final e in values.entries) {
      out = out.replaceAll('{${e.key}}', e.value.split('/').last);
    }
    return out;
  }
}

/// One entry of a project's menu: a page, or a group whose items are pages
/// (written out, or one per child of a parameter's node).
final class ViewNavDef {
  const ViewNavDef({
    this.page,
    this.label,
    this.each,
    this.children = const [],
  });

  final String? page;
  final String? label;

  /// The parameter of [page] that takes one value per child (a group).
  final String? each;
  final List<ViewNavDef> children;
}

/// A view project: the manifest around the pages.
final class ViewProject {
  const ViewProject({
    required this.id,
    required this.title,
    required this.home,
    required this.pages,
    required this.nav,
    this.rotate = const [],
    this.everySeconds = 20,
  });

  /// Reads the manifest; throws a [FormatException] that says what is wrong.
  factory ViewProject.parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, Object?> || j['wyrm_views'] != 1) {
      throw const FormatException('Not a `wyrm_views: 1` manifest.');
    }
    final pages = [
      for (final p in j['pages'] as List? ?? const [])
        if (p case {
          'id': final String id,
          'doc': final String doc,
        })
          ViewPageDef(
            id: id,
            title: p['title'] as String? ?? id,
            doc: doc,
            params: {
              if (p['params'] case final Map<String, Object?> ps)
                for (final e in ps.entries)
                  if (e.value case {'under': final String under}) e.key: under,
            },
          ),
    ];
    if (pages.isEmpty) {
      throw const FormatException('The manifest has no pages.');
    }
    ViewNavDef nav(Object? n) => switch (n) {
      {'page': final String page, 'each': final String each} => ViewNavDef(
        page: page,
        each: each,
      ),
      {'page': final String page} => ViewNavDef(page: page),
      {'label': final String label, 'children': final List<Object?> items} =>
        ViewNavDef(label: label, children: items.map(nav).toList()),
      {'label': final String label, 'children': final Map<String, Object?> c} =>
        ViewNavDef(
          label: label,
          page: c['page'] as String?,
          each: c['each'] as String?,
        ),
      _ => throw FormatException('A menu item is not read: $n'),
    };
    final kiosk = j['kiosk'];
    return ViewProject(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      home: j['home'] as String? ?? pages.first.id,
      pages: pages,
      nav: [for (final n in j['nav'] as List? ?? const []) nav(n)],
      rotate: [
        if (kiosk case {'rotate': final List<Object?> r})
          for (final e in r)
            if (e is String) e,
      ],
      everySeconds: switch (kiosk) {
        {'every_s': final int s} => s,
        _ => 20,
      },
    );
  }

  final String id;
  final String title;
  final String home;
  final List<ViewPageDef> pages;
  final List<ViewNavDef> nav;

  /// `page?param=value` entries the kiosk shows in turn.
  final List<String> rotate;
  final int everySeconds;

  ViewPageDef? page(String id) {
    for (final p in pages) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }

  /// The nodes whose children the menu shows (one item per child).
  Set<String> get listed => {
    for (final n in nav)
      if (n.each case final each?) ?page(n.page ?? '')?.params[each],
  };
}

/// The level a user with [grants] (`(pattern, level)`) has on [key]:
/// the highest of the grants that match it.
String levelOn(String key, List<(String, String)> grants) {
  var best = 0;
  for (final (pattern, level) in grants) {
    if (keyMatches(pattern, key) || keyMatches('$pattern/**', key)) {
      final r = levelRank(level);
      if (r > best) {
        best = r;
      }
    }
  }
  return levels[best];
}

/// A page stays in a viewer's menu when it reads no key at all or the
/// viewer may read at least one of [keys] (§3.3).
bool pageShown(Set<String> keys, List<(String, String)> grants) =>
    keys.isEmpty ||
    keys.any((k) => levelRank(levelOn(k, grants)) >= levelRank('read'));
