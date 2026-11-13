import 'package:models/view_place.dart';

import '../../redux/views/models/views_state.dart';
import 'view_doc.dart';
import 'view_project.dart';

/// The samples of the lab: name → (document, refine turn, project manifest),
/// files of `app/assets/views/`.
const Map<String, ({String doc, String? refine, String? project})> viewSamples =
    {
      'demo-plant': (
        doc: 'demo-plant.a2ui.jsonl',
        refine: null,
        project: 'demo-plant.project.json',
      ),
      'pump-station': (
        doc: 'pump-station.a2ui.jsonl',
        refine: 'pump-station.refine.a2ui.jsonl',
        project: null,
      ),
    };

/// Every file the lab reads.
List<String> get viewSampleFiles => [
  for (final s in viewSamples.values) ...[s.doc, ?s.refine, ?s.project],
  'demo-device.a2ui.jsonl',
];

/// What the lab shows now: the document on screen, and the project and
/// page around it when the *Project* switch is on.
final class ViewNow {
  const ViewNow({
    required this.doc,
    required this.bindings,
    this.project,
    this.page,
    this.place,
    this.fault,
  });

  final ViewDoc doc;
  final ViewBindings bindings;
  final ViewProject? project;
  final ViewPageDef? page;
  final ViewPlace? place;

  /// Why the project is not shown (a manifest that does not read).
  final String? fault;

  /// What is written at the root of the data model: `$name` and `$key` of
  /// the page's first parameter.
  Map<String, Object?> get root => switch (place?.params.values.firstOrNull) {
    final key? => {r'$name': key.split('/').last, r'$key': key},
    null => const {},
  };
}

(ViewsState, ViewNow)? _last;

/// [v] as a [ViewNow]. The answer for the same texts and place is kept, so
/// a connector that asks on every store change parses nothing.
ViewNow viewNow(ViewsState v) {
  if (_last case (final l, final now)?
      when identical(l.docs, v.docs) &&
          l.source == v.source &&
          l.refine == v.refine &&
          l.project == v.project &&
          l.sample == v.sample &&
          l.stack == v.stack) {
    return now;
  }
  final now = _viewNow(v);
  _last = (v, now);
  return now;
}

ViewNow _viewNow(ViewsState v) {
  ViewNow plain([String? fault]) {
    final doc = parseViewDoc(v.source, refine: v.refine);
    return ViewNow(doc: doc, bindings: bindingsOf(doc), fault: fault);
  }

  final manifest = v.docs[viewSamples[v.sample]?.project ?? ''];
  if (!v.project || manifest == null) {
    return plain();
  }
  final ViewProject project;
  try {
    project = ViewProject.parse(manifest);
  } on FormatException catch (e) {
    return plain(e.message);
  }
  final place = v.stack.lastOrNull ?? ViewPlace(page: project.home);
  final page = project.page(place.page);
  if (page == null) {
    return plain('The project has no page `${place.page}`.');
  }
  final doc = parseViewDoc(
    v.docs[page.doc] ?? '',
    params: place.params.unlock,
  );
  return ViewNow(
    doc: doc,
    bindings: bindingsOf(doc),
    project: project,
    page: page,
    place: place,
  );
}

/// The keys the page [id] of [project] reads with [params] (for its badge
/// and for whether it is in a viewer's menu).
Set<String> pageKeys(
  ViewProject project,
  String id,
  Map<String, String> docs, [
  Map<String, String> params = const {},
]) {
  final page = project.page(id);
  if (page == null) {
    return const {};
  }
  return bindingsOf(parseViewDoc(docs[page.doc] ?? '', params: params)).read;
}
