import 'package:wyrm_core/wyrm_core.dart';

/// A driver wyrmd is built with that Studio knows by its code (the
/// `driver` choice of `sys/links` ▸ `install`): `ui` has a title and one
/// line for each, for a broker that does not describe its catalogue (no
/// `attr.catalog`, before ADR 0043).
enum KnownLink implements WireName {
  modbus('modbus'),
  opcua('opcua'),
  bacnet('bacnet'),
  s7('s7'),
  snmp('snmp'),
  mqtt('mqtt'),
  http('http'),
  prometheus('prometheus'),
  dlms('dlms'),
  mock('mock'),
  mockdev('mockdev'),
  s3('s3'),
  gdrive('gdrive'),
  webdav('webdav'),
  localfs('localfs'),
  agent('agent'),
  postgres('postgres'),
  influxdb('influxdb'),
  mongodb('mongodb'),
  mysql('mysql'),
  dynamodb('dynamodb'),
  scheduler('scheduler'),
  alarm('alarm'),
  dql('dql'),
  uplink('uplink');

  const KnownLink(this.wire);

  /// The driver's code on the broker.
  @override
  final String wire;

  static KnownLink? fromWire(String wire) =>
      values.where((l) => l.wire == wire).firstOrNull;
}
