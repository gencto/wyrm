import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/widgets.dart';

/// The app's one store, for the code outside a connector that holds it
/// across awaits: a dialog opened from a page dispatches and reads the state
/// after an await and from its own callbacks, when the context that opened
/// it may be gone. Placed right under the `StoreProvider` (`run_env.dart`).
///
/// async_redux 29 marks its own lookup
/// (`StoreProvider.backdoorInheritedWidget`) `@internal`, and its public
/// context lookups need the context mounted at every call.
final class AppStore extends InheritedWidget {
  const AppStore({required this.store, required super.child, super.key});

  final Store<AppState> store;

  /// The store above [context]. Takes no dependency: the caller is not
  /// rebuilt when the state changes.
  static Store<AppState> of(BuildContext context) {
    final found = context.getInheritedWidgetOfExactType<AppStore>();
    if (found == null) {
      throw StateError('No AppStore above this context.');
    }
    return found.store;
  }

  @override
  bool updateShouldNotify(AppStore oldWidget) => store != oldWidget.store;
}
