/// The actions that cover the app with the modal barrier while they run:
/// what `TopLevelPageConnector` asks the store about.
///
/// **A list, because the store cannot be asked about a mixin.**
/// `Store.isWaiting` compares exact runtime types, so "any action with
/// `BlockingAction`" is not a question it answers; it answers for a list of
/// types. An action says it blocks with the `BlockingAction` mixin *and*
/// stands here. `test/blocking_actions_test.dart` reads the sources of
/// `business` and `app` and fails while the two disagree, in either
/// direction, so the list cannot fall behind the mixin.
///
/// Empty today: the log-in page shows its own progress
/// (docs/design/specs/login.md §3.6–3.7) and no other action blocks.
const blockingActions = <Type>[];
