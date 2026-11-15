import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'link_install_page_words.dart';
import 'support/link_install_app.dart';
import 'support/words_dump.dart';

/// Add a link as the store makes it (studio-rules, step 1): every word of
/// each step on the official, custom (zip, URL, Git, WASM) and backup
/// paths, in English and Ukrainian, and what each control does — read from
/// the fake broker's calls, the file dialog and the screen, not from which
/// actions ran, so it holds before and after the rewrite.
void main() {
  setUp(() => S.load(const Locale('en')));

  Future<LinkInstallApp> shown(
    WidgetTester t, {
    Locale locale = const Locale('en'),
  }) async {
    await S.load(locale);
    final app = LinkInstallApp();
    await app.pump(t, locale: locale);
    return app;
  }

  void words(LinkInstallApp app, WidgetTester t, String name) =>
      expectWordsOf(name, app.words(t), installWords[name] ?? const []);

  group('the official list', () {
    testWidgets('Choose, filter, pick, Where, name, Install', (t) async {
      final app = await shown(t);
      words(app, t, 'official choose');
      await app.type(t, 'post', field: 0);
      words(app, t, 'official search');
      await app.type(t, '', field: 0);
      await app.tap(t, 'History sync');
      words(app, t, 'official category');
      await app.tap(t, 'All');
      await app.tap(t, 'Modbus');
      words(app, t, 'official picked');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'official where');
      await app.type(t, 'a b');
      words(app, t, 'official name rule');
      await app.type(t, 'modbus');
      words(app, t, 'official name taken');
      await app.type(t, 'modbus-2');
      await app.press(t, S.current.install);
      words(app, t, 'official done');
      expect(
        [for (final c in app.calls('install')) c.args],
        [
          Value.from({
            'id': 'modbus-2',
            'driver': 'modbus',
            'mode': 'embedded',
          }),
        ],
      );
      await app.leave(t);
    });

    testWidgets('a mode and a broker that may not take it', (t) async {
      final app = await shown(t);
      await app.tap(t, 'Modbus');
      await app.press(t, S.current.continueLabel);
      await app.tap(t, S.current.modeProcess);
      // `line2` is read only here: its card says why and takes no tap
      await app.tap(t, 'line2');
      words(app, t, 'official where process');
      await app.press(t, S.current.install);
      expect(
        [for (final c in app.calls('install')) c.args],
        [
          Value.from({'id': 'modbus-2', 'driver': 'modbus', 'mode': 'process'}),
        ],
      );
      await app.leave(t);
    });

    testWidgets('a package: its rights are accepted before Install', (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, 'PostgreSQL / TimescaleDB');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'package where');
      await app.tap(t, S.current.acceptRequestedRights);
      words(app, t, 'package accepted');
      await app.press(t, S.current.install);
      expect(
        [for (final c in app.calls('install_repo')) c.args],
        [
          Value.from({
            'name': 'postgres',
            'package': 'postgres',
            'accept': true,
          }),
        ],
      );
      words(app, t, 'package done');
      await app.leave(t);
    });

    testWidgets('Back, the step rail and Add another', (t) async {
      final app = await shown(t);
      await app.tap(t, 'Modbus');
      await app.press(t, S.current.continueLabel);
      await app.press(t, S.current.back);
      words(app, t, 'official back');
      await app.press(t, S.current.continueLabel);
      // the rail's first step goes back to Choose
      await app.tap(t, S.current.stepChoose);
      words(app, t, 'official rail');
      await app.press(t, S.current.continueLabel);
      await app.press(t, S.current.install);
      await app.press(t, S.current.addAnother);
      words(app, t, 'official again');
      await app.leave(t);
    });

    testWidgets('uk: Choose, Where, done', (t) async {
      final app = await shown(t, locale: const Locale('uk'));
      words(app, t, 'uk official choose');
      await app.tap(t, 'Modbus');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'uk official where');
      await app.press(t, S.current.install);
      words(app, t, 'uk official done');
      await app.leave(t);
    });
  });

  group('a custom package', () {
    testWidgets('a zip: picked, checked, installed', (t) async {
      final app = await shown(t);
      await app.tap(t, S.current.customPackage);
      words(app, t, 'custom zip');
      await app.tap(t, S.current.chooseZip);
      expect(app.picker.asked, [
        ['zip'],
      ]);
      words(app, t, 'custom zip picked');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'custom zip check');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'custom zip where');
      await app.press(t, S.current.install);
      words(app, t, 'custom zip done');
      final args = app.calls('install_zip').single.args!;
      expect(args['name'], const VStr('acme-meter'));
      expect(args['zip'], VBytes(packageZip));
      expect(args['accept'], isNull);
      await app.leave(t);
    });

    testWidgets('a URL the broker refuses goes back to its field', (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, S.current.customPackage);
      await app.tap(t, 'URL');
      words(app, t, 'custom url');
      await app.type(t, 'https://example.com/acme.zip');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'custom url check');
      await app.press(t, S.current.continueLabel);
      await app.type(t, 'acme');
      words(app, t, 'custom url where');
      await app.press(t, S.current.install);
      expect(
        [for (final c in app.calls('install_url')) c.args],
        [
          Value.from({'name': 'acme', 'url': 'https://example.com/acme.zip'}),
        ],
      );
      words(app, t, 'custom url failed');
      await app.press(t, S.current.changeAnswers);
      words(app, t, 'custom url refused');
      // a new URL is said no longer refused
      await app.type(t, 'https://example.com/acme-2.zip');
      words(app, t, 'custom url changed');
      await app.leave(t);
    });

    testWidgets('a Git repository with a ref', (t) async {
      final app = await shown(t);
      await app.tap(t, S.current.customPackage);
      await app.tap(t, 'Git');
      words(app, t, 'custom git');
      await app.type(t, 'https://git.example.com/acme.git', field: 0);
      await app.type(t, 'v1.2.0', field: 1);
      await app.press(t, S.current.continueLabel);
      await app.press(t, S.current.continueLabel);
      await app.type(t, 'acme');
      await app.press(t, S.current.install);
      expect(
        [for (final c in app.calls('install_git')) c.args],
        [
          Value.from({
            'name': 'acme',
            'url': 'https://git.example.com/acme.git',
            'ref': 'v1.2.0',
          }),
        ],
      );
      words(app, t, 'custom git done');
      await app.leave(t);
    });

    testWidgets('a WASM component the broker does not install', (t) async {
      final app = await shown(t);
      await app.tap(t, S.current.customPackage);
      await app.tap(t, '.wasm');
      words(app, t, 'custom wasm');
      await app.tap(t, S.current.chooseWasm);
      expect(app.picker.asked, [
        ['wasm'],
      ]);
      await app.press(t, S.current.continueLabel);
      words(app, t, 'custom wasm check');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'custom wasm where');
      await app.press(t, S.current.install);
      final args = app.calls('install_wasm').single.args!;
      expect(args['name'], const VStr('echo'));
      expect(args['wasm'], VBytes(component));
      words(app, t, 'custom wasm failed');
      await app.leave(t);
    });

    testWidgets('a method change drops what was brought', (t) async {
      final app = await shown(t);
      await app.tap(t, S.current.customPackage);
      await app.tap(t, S.current.chooseZip);
      await app.tap(t, 'URL');
      await app.tap(t, S.current.zipFile);
      words(app, t, 'custom zip again');
      await app.leave(t);
    });

    testWidgets('uk: a zip checked', (t) async {
      final app = await shown(t, locale: const Locale('uk'));
      await app.tap(t, S.current.customPackage);
      words(app, t, 'uk custom zip');
      await app.tap(t, S.current.chooseZip);
      await app.press(t, S.current.continueLabel);
      words(app, t, 'uk custom zip check');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'uk custom zip where');
      await app.leave(t);
    });
  });

  group('a link backup', () {
    testWidgets('picked, checked, installed with its passphrase', (t) async {
      final app = await shown(t);
      await app.tap(t, S.current.fromBackup);
      words(app, t, 'backup bring');
      await app.tap(t, S.current.chooseBackupFile);
      expect(app.picker.asked, [
        ['wyrm-link'],
      ]);
      words(app, t, 'backup picked');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'backup check');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'backup where');
      // the passphrase: the last field, under the name
      await app.type(t, 'correct horse');
      await app.tap(t, S.current.acceptRequestedRights);
      await app.press(t, S.current.install);
      expect(
        app.calls('restore_begin').single.args,
        Value.from({
          'size': linkBackup.length,
        }),
      );
      final part = app.calls('restore_part').single.args!;
      expect(part['upload'], const VStr('u1'));
      expect(part['offset'], const VInt(0));
      expect(part['data'], VBytes(Uint8List.fromList(linkBackup)));
      expect(
        [for (final c in app.calls('install_backup')) c.args],
        [
          Value.from({
            'upload': 'u1',
            'id': 'meter',
            'accept': true,
            'passphrase': 'correct horse',
          }),
        ],
      );
      words(app, t, 'backup done');
      await app.leave(t);
    });

    testWidgets('uk: a backup checked', (t) async {
      final app = await shown(t, locale: const Locale('uk'));
      await app.tap(t, S.current.fromBackup);
      await app.tap(t, S.current.chooseBackupFile);
      await app.press(t, S.current.continueLabel);
      words(app, t, 'uk backup check');
      await app.press(t, S.current.continueLabel);
      words(app, t, 'uk backup where');
      await app.leave(t);
    });
  });
}
