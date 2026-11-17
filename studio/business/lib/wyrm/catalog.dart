import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/catalog_category.dart';
import 'package:models/catalog_form.dart';
import 'package:models/catalog_item.dart';
import 'package:models/catalog_row.dart';
import 'package:models/install_target.dart';
import 'package:models/known_link.dart';
import 'package:models/link_category.dart';
import 'package:models/link_mode.dart';

import 'rights.dart';

export 'decode/catalog_rows.dart' show catalogRowsOf;

/// A broker Add a link can install on, as its card shows it: the target,
/// whether it is the site on screen, and why the user may not install
/// there (null: they may), from the grants of now.
final class InstallBroker {
  const InstallBroker(this.target, {required this.here, this.refused});

  final InstallTarget target;
  final bool here;
  final Lack? refused;
}

/// The short tag of a driver Studio knows (`MB`, `PG`): an abbreviation,
/// the same in every language. Its title, its one line and its category's
/// name are `ui`'s words ([KnownLink], [LinkCategory]).
String _tagOf(KnownLink link) => switch (link) {
  .modbus => 'MB',
  .opcua => 'OPC',
  .bacnet => 'BAC',
  .s7 => 'S7',
  .snmp => 'SNMP',
  .mqtt => 'MQTT',
  .http => 'HTTP',
  .prometheus => 'PROM',
  .dlms => 'DLMS',
  .mock => 'MOCK',
  .mockdev => 'DEV',
  .s3 => 'S3',
  .gdrive => 'GD',
  .webdav => 'DAV',
  .localfs => 'FS',
  .agent => 'AI',
  .postgres => 'PG',
  .influxdb => 'INFX',
  .mongodb => 'MDB',
  .mysql => 'MY',
  .dynamodb => 'DDB',
  .scheduler => 'SCH',
  .alarm => 'ALM',
  .dql => 'DQL',
  .uplink => 'UP',
};

/// The category of a driver Studio knows, for a broker that does not
/// describe its catalogue (no `attr.catalog`, before ADR 0043). Which
/// drivers a broker has comes from that broker (`sys/links` ▸ `install`
/// `driver` choices); a driver Studio does not know is still listed, under
/// its own code.
LinkCategory _categoryOf(KnownLink link) => switch (link) {
  .modbus ||
  .opcua ||
  .bacnet ||
  .s7 ||
  .snmp ||
  .mqtt ||
  .http ||
  .prometheus ||
  .dlms => .equipment,
  .mock || .mockdev => .test,
  .s3 || .gdrive || .webdav || .localfs => .fileStores,
  .agent || .scheduler || .alarm || .dql || .uplink => .apps,
  .postgres || .influxdb || .mongodb || .mysql || .dynamodb => .historySync,
};

/// Drivers that run only inside a broker (no process or external mode).
const _embeddedOnly = {'agent', 'wasm', 'app', 'portable-echo', 'storage'};

/// The official list: the broker's drivers, then its repository's packages.
///
/// Which items exist comes from the choices ([drivers], [packages]); the
/// broker's [rows] (`attr.catalog`) only describe them. Without rows (a
/// broker built before ADR 0043) Studio's own names stand, a driver is as
/// new as the broker it is built into ([brokerVersion], its `sys/version`)
/// and a package carries no version. With rows, a package reads only what
/// its own index entry says (ADR 0043 §5: a repository cannot borrow an
/// official description), and only a row marks an item official.
IList<CatalogItem> catalogOf({
  required List<String> drivers,
  required List<String> packages,
  Map<String, int> existing = const {},
  String? brokerVersion,
  Map<String, CatalogRow>? rows,
}) {
  CatalogItem item(String code, {required bool builtIn}) {
    final id = '${builtIn ? 'driver' : 'package'}:$code';
    final row = rows?[id];
    final base = code.replaceAll(RegExp(r'-process$'), '');
    // A package of a broker with rows never takes Studio's text.
    final k = builtIn || rows == null ? KnownLink.fromWire(base) : null;
    final form = switch (row?.form) {
      final f? => f,
      _ when builtIn => CatalogForm.builtin,
      _ when code.endsWith('-process') => CatalogForm.process,
      _ => CatalogForm.wasm,
    };
    final process = !builtIn && form == CatalogForm.process;
    final title = row?.title ?? '';
    final summary = row?.summary ?? '';
    // The broker's title, else Studio's words for a driver it knows, else
    // the code.
    final titled = title.isEmpty ? k : null;
    final version = switch (row?.version) {
      final v? when v.isNotEmpty => v,
      _ when builtIn && brokerVersion != null && brokerVersion.isNotEmpty =>
        brokerVersion,
      _ => null,
    };
    final official = row?.official ?? false;
    return CatalogItem(
      id: id,
      code: code,
      // The short tag of a known link; an unofficial package of a broker
      // with rows gets its own from its name.
      tag: switch (k ?? (official ? KnownLink.fromWire(base) : null)) {
        final known? => _tagOf(known),
        null => code.substring(0, code.length.clamp(0, 4)).toUpperCase(),
      },
      name: title.isNotEmpty ? title : (titled == null ? code : ''),
      titled: titled,
      // Both forms of one link may carry one title: the process form says
      // so.
      processForm: process && !title.toLowerCase().contains('process'),
      description: summary,
      described: summary.isEmpty ? k : null,
      category: switch (row?.category) {
        final c? when c.isNotEmpty => CatalogCategory.of(c),
        _ => CatalogCategory.known(
          switch (k) {
            final known? => _categoryOf(known),
            null => builtIn ? LinkCategory.equipment : LinkCategory.packages,
          },
        ),
      },
      builtIn: builtIn,
      modes: switch (form) {
        _ when builtIn && _embeddedOnly.contains(code) => const IListConst([
          LinkMode.embedded,
        ]),
        _ when builtIn => const IListConst([
          LinkMode.embedded,
          LinkMode.process,
          LinkMode.external,
        ]),
        CatalogForm.process => const IListConst([LinkMode.process]),
        CatalogForm.builtin || CatalogForm.wasm => const IListConst([
          LinkMode.wasm,
        ]),
      },
      existing: existing[builtIn ? code : 'pkg:$code'] ?? 0,
      // A driver's row carries the broker's own version.
      version: version == null ? null : (builtIn ? 'wyrmd $version' : version),
      official: official,
    );
  }

  return [
    for (final d in drivers)
      if (!{'wasm', 'app', 'storage'}.contains(d)) item(d, builtIn: true),
    for (final p in packages) item(p, builtIn: false),
  ].lock;
}

/// The categories of [catalog], each once, in the order of the list.
List<CatalogCategory> categoriesOf(IList<CatalogItem> catalog) => [
  ...{for (final c in catalog) c.category},
];
