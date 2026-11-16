import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/catalog_form.dart';
import 'package:models/catalog_item.dart';
import 'package:models/catalog_row.dart';
import 'package:models/install_target.dart';
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

/// What Studio says of a driver it knows: its short tag, title, one line
/// and category.
final class _Known {
  const _Known(this.tag, this.title, this.summary, this.category);

  final String tag;
  final String title;
  final String summary;
  final String category;
}

/// What Studio knows about the drivers wyrmd is built with (names, one line,
/// category), so the official list reads well on a broker that does not
/// describe its catalogue (no `attr.catalog`, before ADR 0043). Which of
/// them a broker has comes from that broker (`sys/links` ▸ `install`
/// `driver` choices); a driver missing here is still listed, under its own
/// name.
const _known = <String, _Known>{
  'modbus': _Known(
    'MB',
    'Modbus',
    'TCP, RTU over TCP, serial RTU · master and slave',
    'Equipment',
  ),
  'opcua': _Known(
    'OPC',
    'OPC UA client',
    'Nodes of OPC UA servers as points',
    'Equipment',
  ),
  'bacnet': _Known(
    'BAC',
    'BACnet/IP',
    'Who-Is/I-Am, RPM, BBMD, routed devices',
    'Equipment',
  ),
  's7': _Known(
    'S7',
    'Siemens S7',
    'S7-300/400/1200/1500 over ISO-on-TCP',
    'Equipment',
  ),
  'snmp': _Known('SNMP', 'SNMP', 'v2c and v3 agents', 'Equipment'),
  'mqtt': _Known('MQTT', 'MQTT', 'Topics as points', 'Equipment'),
  'http': _Known(
    'HTTP',
    'HTTP / REST',
    'JSON APIs polled on a schedule',
    'Equipment',
  ),
  'prometheus': _Known(
    'PROM',
    'Prometheus',
    'Scrapes exporters into points',
    'Equipment',
  ),
  'dlms': _Known('DLMS', 'DLMS/COSEM', 'Electricity meters', 'Equipment'),
  'mock': _Known(
    'MOCK',
    'Mock',
    'Generated points for tests and benchmarks',
    'Test',
  ),
  'mockdev': _Known(
    'DEV',
    'Mock device',
    'A simulated device on the driver framework',
    'Test',
  ),
  's3': _Known(
    'S3',
    'S3 and compatibles',
    'A bucket as a tree of folders and files',
    'File stores',
  ),
  'gdrive': _Known(
    'GD',
    'Google Drive',
    'A folder or a shared drive',
    'File stores',
  ),
  'webdav': _Known(
    'DAV',
    'WebDAV',
    'Nextcloud, ownCloud and other WebDAV servers',
    'File stores',
  ),
  'localfs': _Known(
    'FS',
    'Local folder',
    'A directory of the host, USB/SD or a mount',
    'File stores',
  ),
  'agent': _Known(
    'AI',
    'Assistant agent',
    'Plans changes for a person to approve',
    'Apps',
  ),
  'postgres': _Known(
    'PG',
    'PostgreSQL / TimescaleDB',
    'Sends the historian’s journal to a database',
    'History sync',
  ),
  'influxdb': _Known(
    'INFX',
    'InfluxDB 2.x / 3.x',
    'Line protocol, tags site and key',
    'History sync',
  ),
  'mongodb': _Known(
    'MDB',
    'MongoDB',
    'History rows as documents',
    'History sync',
  ),
  'mysql': _Known(
    'MY',
    'MySQL / MariaDB',
    'History rows as an upsert per batch',
    'History sync',
  ),
  'dynamodb': _Known(
    'DDB',
    'DynamoDB',
    'History rows with a TTL',
    'History sync',
  ),
  'scheduler': _Known(
    'SCH',
    'Scheduler',
    'Weekly schedules and special days',
    'Apps',
  ),
  'alarm': _Known(
    'ALM',
    'Alarms',
    'Alarm classes, records and acknowledgement',
    'Apps',
  ),
  'dql': _Known(
    'DQL',
    'DQL queries',
    'Tables from the tree, as DSA queries',
    'Apps',
  ),
  'uplink': _Known(
    'UP',
    'Platform upstreams',
    'MQTT, Sparkplug, ThingsBoard, Azure, AWS',
    'Apps',
  ),
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
    final k = builtIn || rows == null ? _known[base] : null;
    final form = switch (row?.form) {
      final f? => f,
      _ when builtIn => CatalogForm.builtin,
      _ when code.endsWith('-process') => CatalogForm.process,
      _ => CatalogForm.wasm,
    };
    final process = !builtIn && form == CatalogForm.process;
    final title = switch (row?.title) {
      final t? when t.isNotEmpty => t,
      _ => k?.title ?? code,
    };
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
      tag:
          (k ?? (official ? _known[base] : null))?.tag ??
          code.substring(0, code.length.clamp(0, 4)).toUpperCase(),
      // Both forms of one link may carry one title: the process form says
      // so.
      name: process && !title.toLowerCase().contains('process')
          ? '$title (process)'
          : title,
      description: switch (row?.summary) {
        final s? when s.isNotEmpty => s,
        _ => k?.summary ?? '',
      },
      category: switch (row?.category) {
        final c? when c.isNotEmpty => c,
        _ => k?.category ?? (builtIn ? 'Equipment' : 'Packages'),
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
List<String> categoriesOf(IList<CatalogItem> catalog) => [
  ...{for (final c in catalog) c.category},
];
