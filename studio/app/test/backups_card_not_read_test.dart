import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/backups_read.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/system_app.dart' hide SysTab;
import 'support/system_app.dart' as app_ show SysTab;

/// The card *Backups* of System › Maintenance when the broker's backups
/// were not read (audit 3 of #135, 1 and 8): it says so, on the screen, in
/// English and in Ukrainian, and never "No backup is kept on the broker"
/// under it. A read that failed offers to read again.
void main() {
  for (final locale in const [Locale('en'), Locale('uk')]) {
    final lang = locale.languageCode;

    testWidgets('attributes in a form Studio does not read ($lang)', (t) async {
      await S.load(locale);
      final app = SystemApp();
      // `sections` is a list of names: this is none
      app.api.metas['$sys/backups'] = NodeMeta(
        attr: {'sections': const VStr('all'), 'keep_days': const VInt(7)},
      );
      await app.pump(t, tab: app_.SysTab.maintenance, locale: locale);

      expect(app.store.state.backups.availability, BackupsRead.unreadable);
      final words = app.words(t);
      expect(words, contains(S.current.bakCard));
      expect(words, contains(S.current.bakNotRead));
      // no list is drawn: the card does not say that none is kept
      expect(words, isNot(contains(S.current.bakCardEmpty)));
      expect(words, isNot(contains('plant-b1.wyrm-backup')));
      expect(words, isNot(contains(S.current.bakReadAgain)));
      expect(
        S.current.bakNotRead,
        contains(lang == 'en' ? 'does not read' : 'не читає'),
      );
      await app.leave(t);
      await S.load(const Locale('en'));
    });

    testWidgets('a read that failed says so and reads again ($lang)', (
      t,
    ) async {
      await S.load(locale);
      final app = SystemApp();
      app.api.errors['$sys/backups'] = WyrmException.of(
        Status.internalError,
        'the broker is busy with itself',
      );
      await app.pump(t, tab: app_.SysTab.maintenance, locale: locale);

      // not "a wyrmd before ADR 0048": the broker said nothing of that
      expect(app.store.state.backups.availability, BackupsRead.failed);
      var words = app.words(t);
      expect(words, contains(S.current.bakReadFailed));
      expect(words, isNot(contains(S.current.bakCardEmpty)));
      expect(words, contains(S.current.bakReadAgain));
      expect(
        S.current.bakReadFailed,
        contains(lang == 'en' ? 'could not be read' : 'Не вдалося прочитати'),
      );

      // the broker answers now: *Read again* brings the kept backups
      app.api.errors.remove('$sys/backups');
      await t.tap(find.text(S.current.bakReadAgain));
      await app.settle(t);
      expect(app.store.state.backups.availability, BackupsRead.read);
      words = app.words(t);
      expect(words, contains('plant-b1.wyrm-backup'));
      expect(words, isNot(contains(S.current.bakReadFailed)));
      expect(words, isNot(contains(S.current.bakReadAgain)));
      await app.leave(t);
      await S.load(const Locale('en'));
    });

    testWidgets('read, and none is kept: only then the card says so ($lang)', (
      t,
    ) async {
      await S.load(locale);
      final app = SystemApp();
      app.api.children_['$sys/backups'] = [];
      await app.pump(t, tab: app_.SysTab.maintenance, locale: locale);

      expect(app.store.state.backups.availability, BackupsRead.read);
      expect(app.words(t), contains(S.current.bakCardEmpty));
      await app.leave(t);
      await S.load(const Locale('en'));
    });
  }
}
