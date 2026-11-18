import 'package:app/connectors/sites_page_connector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:ui/pages/sites_page.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/links_app.dart';
import 'support/screen_app.dart';
import 'support/sites_fixture.dart';
import 'support/system_app.dart';

/// A connection that waits in quarantine and that Studio could not read
/// (a kind it does not know) is on the screens, with words that say so,
/// in English and in Ukrainian: Links › Quarantine, the Sites map, and
/// the Attention list of System (re-audit of #135).
void main() {
  const sys = 'wy/plant/sys';

  /// `gw-9` waits under a kind this Studio does not know.
  void addUnread(FakeWyrmApi api) {
    api
      ..children_['$sys/quarantine'] = [
        ...?api.children_['$sys/quarantine'],
        Child('gw-9', NodeMeta()),
      ]
      ..metas['$sys/quarantine/gw-9'] = NodeMeta(
        display: 'gateway:gw-9',
        attr: {'kind': const VStr('gateway')},
      );
  }

  for (final (locale, kind, chip, note) in [
    (
      const Locale('en'),
      'not read by this Studio',
      'not read',
      'Answered in a form this Studio does not read; decide on the broker. '
          'See Problems.',
    ),
    (
      const Locale('uk'),
      'ця Studio не прочитала',
      'не прочитано',
      'Відповідь у формі, якої ця Studio не читає; вирішуй на брокері. '
          'Дивись Проблеми.',
    ),
  ]) {
    final lang = locale.languageCode;

    testWidgets('Links › Quarantine says "not read" ($lang)', (t) async {
      await S.load(locale);
      final app = LinksApp();
      addUnread(app.api);
      await app.pump(t, locale: locale);
      await app.tap(t, S.current.quarantine);

      final words = app.words(t);
      // the row is there, by its name, and says what it is
      expect(words, contains('gateway:gw-9'));
      expect(words, containsAll([kind, chip, note]));
      // the entries Studio read are worded as before
      expect(words, contains('link:field-gw'));
      await app.leave(t);
      await S.load(const Locale('en'));
    });

    testWidgets('the Sites map says "not read" ($lang)', (t) async {
      final app = ScreenApp();
      sitesBroker(app.api);
      addUnread(app.api);
      await app.logIn(t);
      app.put(withSites);
      await app.pump(t, const SitesPageConnector(), locale: locale);
      await app.settle(t, rounds: 50);

      final words = app.words(t, find.byType(SitesPage));
      // the node is on the map, tagged as not read
      expect(words, containsAllInOrder(['gateway:gw-9', chip]));
      // picked: its inspector says what it is, and offers no Authorize
      await t.tap(find.text('gateway:gw-9'));
      await app.settle(t);
      final picked = app.words(t, find.byType(SitesPage));
      expect(picked, contains(kind.toUpperCase()));
      expect(picked, isNot(contains(S.current.approve)));
      await app.leave(t);
      await S.load(const Locale('en'));
    });

    testWidgets('System › Attention lists it ($lang)', (t) async {
      await S.load(locale);
      final app = SystemApp();
      await app.pump(t, locale: locale);
      // as `RetrieveQuarantineAction` leaves an entry it could not read
      app.put(
        (s) => s.copyWith.quarantine(
          table: s.quarantine.table.add(
            'gw-9',
            const QuarantineEntry(
              cn: 'gateway:gw-9',
              node: 'gw-9',
              kind: QuarantineKind.notRead,
            ),
          ),
          view: s.quarantine.view.add('gw-9'),
        ),
      );
      await app.settle(t);
      await t.pump();

      final words = app.words(t);
      expect(
        words,
        containsAllInOrder([
          S.current.sysAttnNotRead('gw-9'),
          note,
          S.current.sysAttnOpenQuarantine,
        ]),
      );
      expect(
        S.current.sysAttnNotRead('gw-9'),
        contains(lang == 'en' ? 'not read by this Studio' : 'не прочитала'),
      );
      await app.leave(t);
      await S.load(const Locale('en'));
    });
  }
}
