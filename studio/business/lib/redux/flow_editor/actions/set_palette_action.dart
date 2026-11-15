import 'package:models/palette_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetPaletteAction extends Action {
  SetPaletteAction(this.palette);

  final PaletteTab palette;

  @override
  AppState reduce() => state.copyWith.flowEditor(palette: palette);
}
