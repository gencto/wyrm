import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/catalog_item.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'mappers/values.dart';

/// What Studio knows about the drivers wyrmd is built with (names, one line,
/// category), so the official list reads well on a broker that does not
/// describe its catalogue (no `attr.catalog`, before ADR 0043). Which of
/// them a broker has comes from that broker (`sys/links` ▸ `install`
/// `driver` choices); a driver missing here is still listed, under its own
/// name.
const _known = <String, (String, String, String, String)>{
  'modbus': (
    'MB',
    'Modbus',
    'TCP, RTU over TCP, serial RTU · master and slave',
    'Equipment',
  ),
  'opcua': (
    'OPC',
    'OPC UA client',
    'Nodes of OPC UA servers as points',
    'Equipment',
  ),
  'bacnet': (
    'BAC',
    'BACnet/IP',
    'Who-Is/I-Am, RPM, BBMD, routed devices',
    'Equipment',
  ),
  's7': (
    'S7',
    'Siemens S7',
    'S7-300/400/1200/1500 over ISO-on-TCP',
    'Equipment',
  ),
  'snmp': ('SNMP', 'SNMP', 'v2c and v3 agents', 'Equipment'),
  'mqtt': ('MQTT', 'MQTT', 'Topics as points', 'Equipment'),
  'http': (
    'HTTP',
    'HTTP / REST',
    'JSON APIs polled on a schedule',
    'Equipment',
  ),
  'prometheus': (
    'PROM',
    'Prometheus',
    'Scrapes exporters into points',
    'Equipment',
  ),
  'dlms': ('DLMS', 'DLMS/COSEM', 'Electricity meters', 'Equipment'),
  'mock': ('MOCK', 'Mock', 'Generated points for tests and benchmarks', 'Test'),
  'mockdev': (
    'DEV',
    'Mock device',
    'A simulated device on the driver framework',
    'Test',
  ),
  's3': (
    'S3',
    'S3 and compatibles',
    'A bucket as a tree of folders and files',
    'File stores',
  ),
  'gdrive': ('GD', 'Google Drive', 'A folder or a shared drive', 'File stores'),
  'webdav': (
    'DAV',
    'WebDAV',
    'Nextcloud, ownCloud and other WebDAV servers',
    'File stores',
  ),
  'localfs': (
    'FS',
    'Local folder',
    'A directory of the host, USB/SD or a mount',
    'File stores',
  ),
  'agent': (
    'AI',
    'Assistant agent',
    'Plans changes for a person to approve',
    'Apps',
  ),
  'postgres': (
    'PG',
    'PostgreSQL / TimescaleDB',
    'Sends the historian’s journal to a database',
    'History sync',
  ),
  'influxdb': (
    'INFX',
    'InfluxDB 2.x / 3.x',
    'Line protocol, tags site and key',
    'History sync',
  ),
  'mongodb': ('MDB', 'MongoDB', 'History rows as documents', 'History sync'),
  'mysql': (
    'MY',
    'MySQL / MariaDB',
    'History rows as an upsert per batch',
    'History sync',
  ),
  'dynamodb': ('DDB', 'DynamoDB', 'History rows with a TTL', 'History sync'),
  'scheduler': (
    'SCH',
    'Scheduler',
    'Weekly schedules and special days',
    'Apps',
  ),
  'alarm': (
    'ALM',
    'Alarms',
    'Alarm classes, records and acknowledgement',
    'Apps',
  ),
  'dql': ('DQL', 'DQL queries', 'Tables from the tree, as DSA queries', 'Apps'),
  'uplink': (
    'UP',
    'Platform upstreams',
    'MQTT, Sparkplug, ThingsBoard, Azure, AWS',
    'Apps',
  ),
};

/// Drivers that run only inside a broker (no process or external mode).
const _embeddedOnly = {'agent', 'wasm', 'app', 'portable-echo', 'storage'};

/// One row of `attr.catalog` on `sys/links` (ADR 0043 §7): what the broker
/// says of one item of its `install` / `install_repo` choices. An empty
/// text is a field the broker left out.
typedef CatalogRow = ({
  String title,
  String summary,
  String category,
  String version,
  String form,
  bool official,
});

/// The rows of `attr.catalog` by `id` (`driver:<code>` / `package:<code>`);
/// null when the broker sends none (built before ADR 0043).
Map<String, CatalogRow>? catalogRowsOf(Map<String, Value>? attr) {
  final rows = attr?['catalog'];
  if (rows is! VArray) {
    return null;
  }
  String t(Value r, String k) => (str(r[k]) ?? '').trim();
  return {
    for (final r in rows.v)
      if (r is VMap && t(r, 'id').isNotEmpty)
        t(r, 'id'): (
          title: t(r, 'title'),
          summary: t(r, 'summary'),
          category: t(r, 'category'),
          version: t(r, 'version'),
          form: t(r, 'form'),
          official: boolean(r['official']) ?? false,
        ),
  };
}

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
      final f? when f.isNotEmpty => f,
      _ when builtIn => 'builtin',
      _ when code.endsWith('-process') => 'process',
      _ => 'wasm',
    };
    final process = !builtIn && form == 'process';
    final title = switch (row?.title) {
      final t? when t.isNotEmpty => t,
      _ => k?.$2 ?? code,
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
          (k ?? (official ? _known[base] : null))?.$1 ??
          code.substring(0, code.length.clamp(0, 4)).toUpperCase(),
      // Both forms of one link may carry one title: the process form says
      // so.
      name: process && !title.toLowerCase().contains('process')
          ? '$title (process)'
          : title,
      description: switch (row?.summary) {
        final s? when s.isNotEmpty => s,
        _ => k?.$3 ?? '',
      },
      category: switch (row?.category) {
        final c? when c.isNotEmpty => c,
        _ => k?.$4 ?? (builtIn ? 'Equipment' : 'Packages'),
      },
      builtIn: builtIn,
      modes: switch (form) {
        _ when builtIn && _embeddedOnly.contains(code) => const IListConst([
          'embedded',
        ]),
        _ when builtIn => const IListConst(['embedded', 'process', 'external']),
        'process' => const IListConst(['process']),
        _ => const IListConst(['wasm']),
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

/// The categories of [catalog], `All` first.
List<String> categoriesOf(IList<CatalogItem> catalog) => [
  'All',
  ...{for (final c in catalog) c.category},
];
