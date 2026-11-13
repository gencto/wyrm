import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';

import '../../../wyrm/views/view_now.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'pick_view_sample_action.dart';

/// Opens the views lab: reads the sample documents (assets of `app`),
/// keeps [catalog] (part name → the JSON schema of its properties, from
/// the catalog in `ui`) and the viewer's grants for the checks, and shows
/// the sample chosen last.
class OpenViewsLabAction extends Action with WaitingAction {
  OpenViewsLabAction({required this.catalog, this.bundle});

  final Map<String, Object> catalog;

  /// Where the samples are read from; the app's bundle when null.
  final AssetBundle? bundle;

  @override
  Future<AppState?> reduce() async {
    final from = bundle ?? rootBundle;
    final docs = <String, String>{};
    for (final f in viewSampleFiles) {
      docs[f] = await from.loadString('assets/views/$f');
    }
    final me = await deps.session?.me();
    dispatchSync(
      _Opened(docs.lock, catalog.lock, (me?.grants ?? const []).lock),
    );
    dispatchSync(PickViewSampleAction(views.sample));
    return null;
  }
}

class _Opened extends Action {
  _Opened(this.docs, this.catalog, this.grants);

  final IMap<String, String> docs;
  final IMap<String, Object> catalog;
  final IList<(String, String)> grants;

  @override
  AppState reduce() => state.copyWith.views(
    docs: docs,
    catalog: catalog,
    grants: grants,
    open: true,
  );
}
