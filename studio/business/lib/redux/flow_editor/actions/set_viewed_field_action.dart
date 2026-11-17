import 'package:models/field_id.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetViewedFieldAction extends Action {
  SetViewedFieldAction(this.viewedField);

  /// The viewer opened on [row] of [block].
  SetViewedFieldAction.at(String block, RowId row)
    : viewedField = FieldAt(block, row);

  final FieldAt? viewedField;

  @override
  AppState reduce() => state.copyWith.flowEditor(viewedField: viewedField);
}
