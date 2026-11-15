import '../../../wyrm/mappers/flow_problems.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The broker's compiler refused the draft's preview with [message]
/// (null: a draft runs again). The block it names is found here, in the
/// flow as it is now.
class SetPreviewErrorAction extends Action {
  SetPreviewErrorAction(this.message);

  final String? message;

  @override
  AppState reduce() => state.copyWith.flowEditor(
    previewError: switch (message) {
      final m? => brokerProblem(
        m,
        flowEditor.root?.blocks.keys ?? const <String>[],
      ),
      null => null,
    },
  );
}
