import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'open_view_page_action.dart';

/// One action of a surface, after the viewer confirmed it
/// (docs/design/specs/genui-views.md §3.1): `wyrm.set {key, value}`,
/// `wyrm.invoke {key, action, args?}` or `wyrm.open {page, params}`. The
/// call is made with the viewer's session; a refusal is an error of
/// docs/design/specs/errors.md like any other write.
class RunViewAction extends Action with WaitingAction {
  RunViewAction(this.name, this.context);

  final String name;
  final Map<String, Object?> context;

  @override
  Action again() => RunViewAction(name, context);

  @override
  Future<AppState?> reduce() async {
    switch (name) {
      case 'wyrm.set':
        final key = context['key'];
        final value = context['value'];
        if (key is! String || key.isEmpty || value == null) {
          throw StudioException.studio(
            'The value was not written',
            message: 'The view names no key or no value to write.',
            call: 'set',
          );
        }
        await call(
          'set',
          key,
          () => deps.wyrm.set(key, Value.from(value)),
          write: true,
        );
        return state.copyWith.views(result: 'Wrote $value to $key');
      case 'wyrm.invoke':
        final key = context['key'];
        final action = context['action'];
        if (key is! String || action is! String) {
          throw StudioException.studio(
            'The action was not run',
            message: 'The view names no key or no action to run.',
            call: 'invoke',
          );
        }
        final args = context['args'];
        final rows = await invokeAll(
          deps.wyrm,
          key,
          action,
          args is Map && args.isNotEmpty ? Value.from(args) : null,
        );
        for (final r in rows) {
          requireSuccess(r, key, action);
        }
        return state.copyWith.views(
          result: rows.isEmpty
              ? 'Ran $action on $key'
              : 'Ran $action on $key: ${toDart(rows.first)}',
        );
      case 'wyrm.open':
        final page = context['page'];
        final params = context['params'];
        await null;
        dispatchSync(
          OpenViewPageAction(
            page is String ? page : '',
            params: {
              if (params is Map)
                for (final e in params.entries)
                  if (e.value case final String v) '${e.key}': v,
            },
          ),
        );
        return null;
      default:
        throw StudioException.studio(
          'The action was not run',
          message: 'Studio runs no action named `$name`.',
        );
    }
  }
}
