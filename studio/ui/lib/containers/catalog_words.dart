import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

// The words of the official list that are Studio's own (studio-rules §3,
// §5): the title and the one line of a driver Studio knows, the name of a
// category of the manifest. What a broker says of an item is shown as it
// came.

/// A driver Studio has words for: its title and its one line, for a broker
/// that describes no catalogue.
enum LinkWords {
  modbus,
  opcua,
  bacnet,
  s7,
  snmp,
  mqtt,
  http,
  prometheus,
  dlms,
  mock,
  mockdev,
  s3,
  gdrive,
  webdav,
  localfs,
  agent,
  postgres,
  influxdb,
  mongodb,
  mysql,
  dynamodb,
  scheduler,
  alarm,
  dql,
  uplink;

  String get title {
    final s = S.current;
    return switch (this) {
      modbus => s.linkTitleModbus,
      opcua => s.linkTitleOpcua,
      bacnet => s.linkTitleBacnet,
      s7 => s.linkTitleS7,
      snmp => s.linkTitleSnmp,
      mqtt => s.linkTitleMqtt,
      http => s.linkTitleHttp,
      prometheus => s.linkTitlePrometheus,
      dlms => s.linkTitleDlms,
      mock => s.linkTitleMock,
      mockdev => s.linkTitleMockdev,
      s3 => s.linkTitleS3,
      gdrive => s.linkTitleGdrive,
      webdav => s.linkTitleWebdav,
      localfs => s.linkTitleLocalfs,
      agent => s.linkTitleAgent,
      postgres => s.linkTitlePostgres,
      influxdb => s.linkTitleInfluxdb,
      mongodb => s.linkTitleMongodb,
      mysql => s.linkTitleMysql,
      dynamodb => s.linkTitleDynamodb,
      scheduler => s.linkTitleScheduler,
      alarm => s.linkTitleAlarm,
      dql => s.linkTitleDql,
      uplink => s.linkTitleUplink,
    };
  }

  String get summary {
    final s = S.current;
    return switch (this) {
      modbus => s.linkSummaryModbus,
      opcua => s.linkSummaryOpcua,
      bacnet => s.linkSummaryBacnet,
      s7 => s.linkSummaryS7,
      snmp => s.linkSummarySnmp,
      mqtt => s.linkSummaryMqtt,
      http => s.linkSummaryHttp,
      prometheus => s.linkSummaryPrometheus,
      dlms => s.linkSummaryDlms,
      mock => s.linkSummaryMock,
      mockdev => s.linkSummaryMockdev,
      s3 => s.linkSummaryS3,
      gdrive => s.linkSummaryGdrive,
      webdav => s.linkSummaryWebdav,
      localfs => s.linkSummaryLocalfs,
      agent => s.linkSummaryAgent,
      postgres => s.linkSummaryPostgres,
      influxdb => s.linkSummaryInfluxdb,
      mongodb => s.linkSummaryMongodb,
      mysql => s.linkSummaryMysql,
      dynamodb => s.linkSummaryDynamodb,
      scheduler => s.linkSummaryScheduler,
      alarm => s.linkSummaryAlarm,
      dql => s.linkSummaryDql,
      uplink => s.linkSummaryUplink,
    };
  }
}

/// A category of the manifest, as its chip names it.
enum LinkCategoryTag {
  equipment,
  apps,
  fileStores,
  historySync,
  messaging,
  test,
  packages;

  String get label {
    final s = S.current;
    return switch (this) {
      equipment => s.linkCategoryEquipment,
      apps => s.linkCategoryApps,
      fileStores => s.linkCategoryFileStores,
      historySync => s.linkCategoryHistorySync,
      messaging => s.linkCategoryMessaging,
      test => s.linkCategoryTest,
      packages => s.linkCategoryPackages,
    };
  }
}

/// A category chip of the official list: one of the manifest's, or the
/// text a broker gave.
sealed class CatalogCategoryVm extends Equatable {
  const CatalogCategoryVm();

  /// What the chip reads.
  String get label;

  /// What tells the chips apart, the same in every language.
  String get chipKey;
}

final class CatalogCategoryKnownVm extends CatalogCategoryVm {
  const CatalogCategoryKnownVm(this.tag);

  final LinkCategoryTag tag;

  @override
  String get label => tag.label;

  @override
  String get chipKey => tag.name;

  @override
  List<Object?> get props => [tag];
}

final class CatalogCategoryNamedVm extends CatalogCategoryVm {
  const CatalogCategoryNamedVm(this.name);

  final String name;

  @override
  String get label => name;

  @override
  String get chipKey => '=$name';

  @override
  List<Object?> get props => [name];
}

/// The title of an item of the official list: the broker's [name], or
/// Studio's words for a driver it knows ([titled]); a process package
/// whose title does not say so reads `<title> (process)` ([process]).
final class CatalogTitleVm extends Equatable {
  const CatalogTitleVm({this.name = '', this.titled, this.process = false});

  final String name;
  final LinkWords? titled;
  final bool process;

  String get text {
    final title = titled?.title ?? name;
    return process ? S.current.catalogProcessForm(title) : title;
  }

  @override
  List<Object?> get props => [name, titled, process];
}
