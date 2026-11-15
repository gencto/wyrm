import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'load_assistant_action.dart';
import 'set_shown_action.dart';
import 'set_watched_action.dart';

/// The Assistant tab is shown or hidden (its `TabVisibility`). Shown, it
/// watches the keys its Result card shows (and *Today* of What it may do)
/// and reads the site's agent and its tasks; hidden, it lets the keys go.
///
/// One intent, one dispatch (studio-rules §9): the flag is not drawn (it
/// does not notify); the watches are one change; the read that follows has
/// its own waits and notifies for what it changes.
class ShowAssistantAction extends Action {
  ShowAssistantAction({required this.shown});

  final bool shown;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(SetShownAction(shown), notify: false);
    dispatchSync(
      SetWatchedAction((shown ? assistantWatch : const <String>[]).lock),
    );
    if (shown) {
      await dispatchAndWait(LoadAssistantAction());
    }
    return null;
  }
}
