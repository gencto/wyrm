import 'package:models/links_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../updates/models/updates_state.dart';

/// *Open <link>* of an update's result: the sheet closes and the link is
/// selected on *On this broker*, in one state.
class ShowLinkHereAction extends Action {
  ShowLinkHereAction(this.link);

  final String link;

  @override
  AppState reduce() => state.copyWith(
    updates: const UpdatesState(),
    links: state.links.copyWith(tab: LinksTab.local, selectedLink: link),
  );
}
