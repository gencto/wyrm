import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Selects one block (it alone), or nothing.
class SetSelectedBlockAction extends Action {
  SetSelectedBlockAction(this.selectedBlock);

  final String? selectedBlock;

  @override
  AppState reduce() => state.copyWith.flowEditor(
    selectedBlock: selectedBlock,
    selection: switch (selectedBlock) {
      final id? => {id}.toISet(),
      null => const ISetConst({}),
    },
  );
}
