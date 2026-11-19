import 'package:models/catalog_category.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The category of the official list on screen; null: all of them.
class SetCategoryAction extends Action {
  SetCategoryAction(this.category);

  final CatalogCategory? category;

  @override
  AppState reduce() => state.copyWith.linkInstall(category: category);
}
