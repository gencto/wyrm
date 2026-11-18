import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:models/studio_error.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Adds one failure to Problems (docs/design/specs/errors.md §4): every
/// error, shown in a dialog or not, is a line there until Studio quits.
/// Newest first, at most [problemLimit]. A failure of the same call with
/// the same status as one already listed replaces it (a poll that fails
/// every two seconds is one line, not hundreds). A quiet one also raises a
/// toast.
class AddProblemAction extends Action {
  AddProblemAction(this.error);

  final StudioError error;

  @override
  AppState reduce() => problemAdded(state, error);
}

/// How many problems are kept.
const problemLimit = 200;

/// What makes two failures the same line.
List<Object?> _same(StudioError e) => [
  e.kind,
  e.status?.code,
  e.key,
  e.call,
  e.foreign,
  e.hint,
  e.subject,
  e.thing,
  e.site,
  e.stream,
];

/// [state] with [error] in Problems (see [AddProblemAction]).
AppState problemAdded(AppState state, StudioError error) {
  final p = state.problems;
  // One that did not come through an action (a stream, a widget that
  // threw) gets its id, time and site here.
  final e = error.copyWith(
    id: error.id == 0 ? nextErrorId() : error.id,
    at: error.at ?? DateTime.now(),
    site: error.site ?? SelectSite(state).viewed,
  );
  final same = _same(e);
  final old = p.items.where((o) => listEquals(_same(o), same)).firstOrNull;
  final items = [
    e,
    ...p.items.where((o) => o.id != old?.id),
  ].take(problemLimit).toIList();
  final toasts = p.toasts.where((id) => id != old?.id).toIList();
  return state.copyWith.problems(
    items: items,
    // The drawer is open: the user is looking at the list.
    unread: p.open || old != null ? p.unread : p.unread + 1,
    toasts: e.quiet ? toasts.add(e.id) : toasts,
  );
}
