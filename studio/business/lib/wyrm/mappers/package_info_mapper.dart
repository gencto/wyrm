import 'package:models/package_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The full `~meta` of `sys/packages/<name>` (`wy:package`) as a
/// [PackageInfo].
PackageInfo packageInfoOf(String name, NodeMeta m) => PackageInfo(
  name: name,
  version: str(attrOf(m, 'version')) ?? '',
  kind: str(attrOf(m, 'kind')) ?? 'process',
  source: str(attrOf(m, 'source')),
  sha256: str(attrOf(m, 'sha256')),
);
