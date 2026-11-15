import '../../app_state.dart';
import '../../common/action.dart';

/// Puts [text] on the system clipboard (`AppDependencies.clipboard`); a
/// platform without one keeps only the editor's own copy.
class WriteClipboardAction extends Action {
  WriteClipboardAction(this.text);

  final String text;

  @override
  Future<AppState?> reduce() async {
    await deps.clipboard.write(text);
    return null;
  }
}
