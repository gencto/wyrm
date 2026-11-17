import 'dart:convert';
import 'dart:typed_data';

import 'package:app/common/app_store.dart';
import 'package:app/connectors/link_install_page_connector.dart';
import 'package:archive/archive.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/site/actions/retrieve_sites_action.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../business/test/support/fake_wyrm.dart';
import 'links_app.dart' show ignoreOverflow;

export '../../../business/test/support/fake_wyrm.dart';

/// The site of every Add a link test.
const plant = 'wy/plant';

/// `wy/plant/sys`.
const sys = '$plant/sys';

/// A zip of [files] by name.
Uint8List zipOf(Map<String, List<int>> files) {
  final a = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    a.addFile(ArchiveFile.bytes(key, value));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

List<int> _json(Object o) => utf8.encode(jsonEncode(o));

/// A process package for any host, asking for no rights.
final Uint8List packageZip = zipOf({
  'wyrm-link.json': _json({
    'name': 'acme-meter',
    'version': '1.2.0',
    'wyrm_link': 1,
    'kind': 'process',
    'entries': {'linux-aarch64': 'bin/acme', 'macos-aarch64': 'bin/acme'},
  }),
  'bin/acme': [1, 2, 3],
});

/// One WASM component: its magic and version, nothing more.
final component = Uint8List.fromList([
  0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00, //
]);

/// A link backup of `meter`, sealed with a passphrase, its package inside.
final Uint8List linkBackup = zipOf({
  'manifest.json': _json({
    'wyrm_backup': 1,
    'kind': 'link',
    'site': 'plant',
    'broker': '0.1.0',
    'created': '2026-11-12T01:00:00Z',
    'link': {
      'id': 'meter',
      'mode': 'process',
      'driver': 'pkg:acme-meter',
      'package': 'acme-meter',
      'version': '1.2.0',
    },
    'sections': [
      {'name': 'settings'},
      {'name': 'package'},
    ],
    'sealed': {'how': 'passphrase'},
  }),
  'settings.json': _json({'host': '10.0.4.9'}),
});

/// A file the system's file dialog hands back: bytes, no path.
final class _Picked extends PlatformFile {
  _Picked(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.parse('memory:$name');

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

/// The system's file dialog: it answers with the file of the extension
/// asked for, and records the extensions of each call.
final class FakeFilePicker extends FilePickerPlatform {
  final asked = <List<String>>[];

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final ext = allowedExtensions ?? const [];
    asked.add(ext);
    return switch (ext) {
      ['zip'] => _Picked('acme-meter-1.2.0.zip', packageZip),
      ['wasm'] => _Picked('echo.wasm', component),
      ['wyrm-link'] => _Picked('meter.wyrm-link', linkBackup),
      _ => null,
    };
  }
}

/// Add a link over a fake gateway: the site `plant` (config there) with a
/// broker below it (`line2`, read only), two drivers and one repository
/// package to offer, one link `modbus` already there, and answers for
/// each install call.
class LinkInstallApp {
  LinkInstallApp()
    : login = FakeLogin(
        session: FakeSession(
          who: identityOf(
            subject: 'user:olena',
            site: 'plant',
            roles: const ['admin'],
            max: 'config',
            grants: const [
              ('$plant/**', 'config'),
              ('wy/line2/**', 'read'),
            ],
          ),
        ),
      ) {
    store = fakeStore(login: login);
    _broker();
  }

  final FakeLogin login;
  late final Store<AppState> store;
  final picker = FakeFilePicker();

  FakeWyrmApi get api => login.session.api;

  void _broker() {
    ValSample stored(String key, Value v) => ValSample(key, Sample(v, t: 0));
    api
      ..metas['$sys/links'] = NodeMeta(
        attr: {
          'catalog': Value.from([
            {
              'id': 'driver:modbus',
              'title': 'Modbus',
              'summary': 'TCP, RTU over TCP, serial RTU',
              'category': 'Equipment',
              'version': '0.1.0',
              'form': 'builtin',
              'official': true,
            },
            {
              'id': 'package:postgres',
              'title': 'PostgreSQL / TimescaleDB',
              'summary': 'Sends the historian journal to a database',
              'category': 'History sync',
              'version': '0.4.0',
              'form': 'wasm',
              'official': true,
            },
          ]),
        },
        actions: {
          'install': ActionMeta(
            level: Perm.config,
            params: {
              'driver': ParamMeta(
                ty: TypeCode.enum_,
                enumValues: const ['modbus', 'mock'],
              ),
            },
          ),
          'install_repo': ActionMeta(
            level: Perm.config,
            params: {
              'package': ParamMeta(
                ty: TypeCode.enum_,
                enumValues: const ['postgres'],
              ),
            },
          ),
        },
      )
      ..children_['$sys/links'] = [Child('modbus', NodeMeta())]
      ..metas['$sys/links/modbus'] = NodeMeta(
        attr: {'driver': const VStr('modbus'), 'mode': const VStr('embedded')},
      )
      ..initial['$sys/version'] = [stored('$sys/version', const VStr('0.1.0'))]
      ..initial['$sys/distribution'] = [
        stored('$sys/distribution', const VStr('rust (prod)')),
      ]
      ..initial['wy/line2/sys/distribution'] = [
        stored('wy/line2/sys/distribution', const VStr('linux-aarch64')),
      ]
      ..children_['$plant/downstream'] = [
        Child('line2', NodeMeta(is_: const TText('wy:broker'))),
      ]
      ..children_['wy/line2/downstream'] = const []
      ..errors['$sys/upstream'] = WyrmException.of(Status.notFound, 'none')
      ..invokes['$sys/links ▸ install'] = [
        Value.from({'success': true, 'message': 'link modbus-2 installed'}),
      ]
      ..invokes['$sys/links ▸ install_repo'] = [
        Value.from({'success': true, 'message': 'link postgres installed'}),
      ]
      ..invokes['$sys/links ▸ install_zip'] = [
        Value.from({'success': true, 'message': 'link acme-meter installed'}),
      ]
      ..invokes['$sys/links ▸ install_wasm'] = [
        Value.from({'success': false, 'message': 'no world wyrm:app'}),
      ]
      ..invokes['$sys/links ▸ install_git'] = [
        Value.from({'success': true, 'message': 'link acme installed'}),
      ]
      ..errors['$sys/links ▸ install_url'] = WyrmException.of(
        Status.invalidParameter,
        'url: host not reachable',
      )
      ..invokes['$sys/backups ▸ restore_begin'] = [
        // as the broker answers: {upload, part_size, max_part}
        Value.from({
          'upload': 'u1',
          'part_size': 1 << 20,
          'max_part': 16 << 20,
        }),
      ]
      ..invokes['$sys/backups ▸ restore_part'] = const [VNull()]
      ..invokes['$sys/links ▸ install_backup'] = [
        Value.from({'success': true, 'message': 'link meter installed'}),
      ];
  }

  /// Logs in and shows Add a link in [locale].
  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ignoreOverflow();
    final was = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = was);
    await tester.runAsync(() async {
      await store.dispatchAndWait(SetGatewayAction('http://g'));
      await store.dispatchAndWait(SetUserAction('olena'));
      await store.dispatchAndWait(SetPasswordAction('pw'));
      await store.dispatchAndWait(LogInAction());
      await store.dispatchAndWait(RetrieveSitesAction());
      // the links of the site, as the Links screen read them before
      await store.dispatchAndWait(RetrieveLinksAction());
    });
    await tester.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: AppStore(
          store: store,
          child: MaterialApp(
            theme: darkTheme(),
            locale: locale,
            supportedLocales: S.delegate.supportedLocales,
            localizationsDelegates: const [
              S.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: const LinkInstallPageConnector(),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Lets the fake broker's answers arrive and the screen follow them.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Taps the text [label] on Add a link (a card, a tab, a button).
  Future<void> tap(WidgetTester tester, String label) async {
    final f = find.descendant(
      of: find.byType(LinkInstallPageConnector),
      matching: find.text(label),
    );
    await tester.ensureVisible(f.first);
    await tester.tap(f.first);
    await settle(tester);
  }

  /// Presses the button [label] (Back, Continue, Install, a result's).
  Future<void> press(WidgetTester tester, String label) async {
    final f = find.descendant(
      of: find.byType(LinkInstallPageConnector),
      matching: find.widgetWithText(Button, label),
    );
    await tester.ensureVisible(f.first);
    await tester.tap(f.first);
    await settle(tester);
  }

  /// Types [text] into the text field at [field], in the order of the
  /// tree (the last one when null).
  Future<void> type(WidgetTester tester, String text, {int? field}) async {
    final fields = find.descendant(
      of: find.byType(LinkInstallPageConnector),
      matching: find.byType(EditableText),
    );
    final f = field == null ? fields.last : fields.at(field);
    await tester.ensureVisible(f);
    await tester.enterText(f, text);
    await settle(tester);
  }

  /// Every word on Add a link, in the order of the tree.
  List<String> words(WidgetTester tester) => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(LinkInstallPageConnector),
        matching: find.byType(RichText),
      ),
    ))
      w.text.toPlainText(),
  ];

  /// The calls of [action] (an invoke's name) made so far.
  List<Call> calls(String action) => [
    for (final c in api.calls)
      if (c.action == action) c,
  ];

  /// Takes Add a link off the screen.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }
}
