import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/catalog_item.dart';

/// What Studio knows about the drivers wyrmd is built with (names, one line,
/// category), so the official list reads well. Which of them a broker has
/// comes from that broker (`sys/links` ▸ `install` `driver` choices); a
/// driver missing here is still listed, under its own name.
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

/// The official list: the broker's drivers, then its repository's packages.
/// A driver is as new as the broker it is built into ([brokerVersion], its
/// `sys/version`); the repository's choices carry no version.
IList<CatalogItem> catalogOf({
  required List<String> drivers,
  required List<String> packages,
  Map<String, int> existing = const {},
  String? brokerVersion,
}) {
  CatalogItem item(String code, {required bool builtIn}) {
    final base = code.replaceAll(RegExp(r'-process$'), '');
    final k = _known[base];
    final process = code.endsWith('-process');
    return CatalogItem(
      id: '${builtIn ? 'driver' : 'package'}:$code',
      code: code,
      tag: k?.$1 ?? code.substring(0, code.length.clamp(0, 4)).toUpperCase(),
      name: k == null ? code : (process ? '${k.$2} (process)' : k.$2),
      description: k?.$3 ?? '',
      category: k?.$4 ?? (builtIn ? 'Equipment' : 'Packages'),
      builtIn: builtIn,
      modes: builtIn
          ? (_embeddedOnly.contains(code)
                ? const IListConst(['embedded'])
                : const IListConst(['embedded', 'process', 'external']))
          : (process
                ? const IListConst(['process'])
                : const IListConst(['wasm'])),
      existing: existing[builtIn ? code : 'pkg:$code'] ?? 0,
      version: builtIn && brokerVersion != null && brokerVersion.isNotEmpty
          ? 'wyrmd $brokerVersion'
          : null,
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
