import 'package:wyrm_client/wyrm_client.dart' show Status;

import '../../app_state.dart';
import '../../common/action.dart';

class SetPreviewOffAction extends Action {
  SetPreviewOffAction(this.previewOff);

  final Status? previewOff;

  @override
  AppState reduce() => state.copyWith.flowEditor(previewOff: previewOff);
}
