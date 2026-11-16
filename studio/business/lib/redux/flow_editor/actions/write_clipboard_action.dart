import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The one queue of the system clipboard: its writes and the reads of a
/// paste run one at a time, in the order they were dispatched, so a paste
/// reads the last copy and two copies end with the second.
const clipboardQueue = #clipboard;

/// Puts [text] on the system clipboard (`AppDependencies.clipboard`); a
/// platform without one keeps only the editor's own copy. Started by a copy
/// that does not wait for it, so it runs in [clipboardQueue]: a later
/// copy's write never lands before it.
class WriteClipboardAction extends Action with Sequential<AppState> {
  WriteClipboardAction(this.text);

  final String text;

  @override
  Object? sequentialKeyParams() => clipboardQueue;

  @override
  Future<AppState?> reduce() async {
    await deps.clipboard.write(text);
    return null;
  }
}
