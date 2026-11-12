import 'dart:collection';

import 'package:async_redux/async_redux.dart';
import 'package:material_ui/material_ui.dart';

/// Takes each `UserException` off the store's error queue and hands it to
/// [onShowUserExceptionDialog] after the frame (async_redux's
/// `UserExceptionDialog`, kept here so the dialog itself is the app's).
class ExceptionDialog<St> extends StatelessWidget {
  const ExceptionDialog({
    required this.child,
    required this.onShowUserExceptionDialog,
    super.key,
    this.useLocalContext = false,
  });
  final Widget child;

  /// Shows one queued `UserException`. There is no default: the app's own
  /// dialog is `showUserException` (`error_dialogs.dart`,
  /// docs/design/specs/errors.md §3), not a Material `AlertDialog`.
  final ShowUserExceptionDialog onShowUserExceptionDialog;

  /// If false (the default), the dialog will appear in the context of the
  /// [NavigateAction.navigatorKey]. If you don't set up that key, or if you
  /// pass `true` here, it will use the local context of the
  /// [UserExceptionDialog] widget.
  ///
  /// Make sure this is `false` if you are putting the [UserExceptionDialog] in
  /// the `builder` parameter of the [MaterialApp] widget, because in this case
  /// the [UserExceptionDialog] will be above the app's [Navigator], and if
  /// you open the dialog in the local context you won't be able to use the
  /// Android back-button to close it.
  final bool useLocalContext;

  @override
  Widget build(BuildContext context) => StoreConnector<St, _Vm>(
    vm: _Factory<St>.new,
    builder: (context, vm) {
      //
      final errorEvent = //
          (_Factory._errorEvents.isEmpty) //
          ? null
          : _Factory._errorEvents.removeFirst();

      return _UserExceptionDialogWidget(
        errorEvent: errorEvent,
        useLocalContext: useLocalContext,
        onShowUserExceptionDialog: onShowUserExceptionDialog,
        child: child,
      );
    },
  );
}

class _UserExceptionDialogWidget extends StatefulWidget {
  const _UserExceptionDialogWidget({
    required this.child,
    required this.errorEvent,
    required this.useLocalContext,
    required this.onShowUserExceptionDialog,
  });
  final Widget child;
  final Event<UserException>? errorEvent;
  final ShowUserExceptionDialog onShowUserExceptionDialog;
  final bool useLocalContext;

  @override
  _UserExceptionDialogState createState() => _UserExceptionDialogState();
}

class _UserExceptionDialogState extends State<_UserExceptionDialogWidget> {
  @override
  void didUpdateWidget(_UserExceptionDialogWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final userException = widget.errorEvent?.consume();

    if (userException != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onShowUserExceptionDialog(
          context: context,
          userException: userException,
          useLocalContext: widget.useLocalContext,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Factory<St> extends VmFactory<St, UserExceptionDialog<dynamic>, _Vm> {
  static final Queue<Event<UserException>> _errorEvents = Queue();

  @override
  _Vm fromStore() {
    final error = getAndRemoveFirstError();

    if (error != null) {
      _errorEvents.add(Event(error));
    }

    return _Vm(rebuild: error != null);
  }
}

class _Vm extends Vm {
  _Vm({required this.rebuild});
  //
  final bool rebuild;

  /// Does not respect equals contract:
  /// Is not equal when it should rebuild.
  @override
  bool operator ==(Object other) => !rebuild;

  @override
  int get hashCode => rebuild.hashCode;
}

typedef ShowUserExceptionDialog = void Function({
  required BuildContext context,
  required UserException userException,
  required bool useLocalContext,
});
