import 'package:business/redux/language/actions/set_language_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/pages/explorer_page.dart';

import 'support/explorer_app.dart';

/// A page whose view-model compares equal is not built again by a dispatch
/// elsewhere; a change of the language is not one of those: the words it
/// draws (`S.current`) follow at once, and the page keeps what it holds.
void main() {
  setUp(() => S.load(const Locale('en')));
  tearDown(() => S.load(const Locale('en')));

  testWidgets('a mounted Explorer follows the language', (t) async {
    final app = ExplorerApp();
    await app.pump(t, language: true);
    await t.tap(
      find
          .byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == 'plc1',
          )
          .first,
    );
    await app.settle(t);
    Finder words(String s) =>
        find.descendant(of: find.byType(ExplorerPage), matching: find.text(s));
    expect(words('Parameters'), findsOneWidget);
    final state = t.state(find.byType(ExplorerPage));

    app.store.dispatchSync(SetLanguageAction('uk'));
    await app.settle(t);
    expect(words('Параметри'), findsOneWidget);
    expect(words('Parameters'), findsNothing);
    expect(t.state(find.byType(ExplorerPage)), same(state));
    expect(app.store.state.language.locale, 'uk');
  });
}
