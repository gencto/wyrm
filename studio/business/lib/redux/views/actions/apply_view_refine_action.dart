import '../../../wyrm/views/view_now.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'sync_view_action.dart';

/// Applies the sample's second file (the refine turn) on top of what is
/// shown, or [text] when given. The surface stays: only the new messages
/// reach it, and the values it already has are kept.
class ApplyViewRefineAction extends Action with SyncsView {
  ApplyViewRefineAction([this.text]);

  final String? text;

  @override
  AppState? reduce() {
    final turn = text ?? views.docs[viewSamples[views.sample]?.refine ?? ''];
    if (turn == null || turn == views.refine) {
      return null;
    }
    syncView = true;
    return state.copyWith.views(refine: turn);
  }
}
