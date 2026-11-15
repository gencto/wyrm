import 'package:wyrm_core/wyrm_core.dart';

/// The action of `sys/links` that installs a link (docs/links.md §5), by
/// where it comes from.
enum LinkInstallCall implements WireName {
  /// A driver built into the broker.
  builtIn('install'),

  /// A package of the broker's repository.
  repository('install_repo'),

  /// A package zip sent whole.
  zip('install_zip'),

  /// A package zip at a URL.
  url('install_url'),

  /// A Git repository with a built package.
  git('install_git'),

  /// One WASM component sent whole.
  wasm('install_wasm'),

  /// A link backup uploaded in parts to `sys/backups`.
  backup('install_backup');

  const LinkInstallCall(this.wire);

  @override
  final String wire;
}
