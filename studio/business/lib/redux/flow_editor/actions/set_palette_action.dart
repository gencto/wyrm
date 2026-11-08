import '../../app_state.dart';
import '../../common/action.dart';

class SetPaletteAction extends Action {
  SetPaletteAction(this.palette);

  final String palette;

  @override
  AppState reduce() => state.copyWith.flowEditor(palette: palette);
}
