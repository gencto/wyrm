import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/site_choice.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetChoicesAction extends Action {
  SetChoicesAction(this.choices);

  final IList<SiteChoice> choices;

  @override
  AppState reduce() => state.copyWith.site(choices: choices);
}
