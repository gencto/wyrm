/// A number the broker serves under `sys` that System shows
/// (specs/system.md, Data), by its key below `sys`.
enum SysValue {
  linksConnected('links_connected'),
  linksTotal('links_total'),
  quarantined('quarantined'),
  packagesTotal('packages_total'),
  upstreamConnected('upstream_connected'),
  downstreamConnected('downstream_connected'),
  sessions('sessions'),
  cpu('cpu'),

  /// MiB, as `diskFree` and `dataSize`.
  memory('memory'),
  diskFree('disk_free'),
  dataSize('data_size'),

  /// The historian's own size, MiB.
  historySize('history/database_size'),
  aclDenied('acl_denied'),
  auditRecords('audit_records'),

  /// Seconds since the broker started.
  uptime('uptime'),
  standbyConnected('standby_connected'),
  standbyLag('standby_lag'),
  standbyForks('standby_forks'),
  arbiterLease('arbiter_lease_s'),
  messagesIn('messages_in_per_second'),
  messagesOut('messages_out_per_second'),
  framesIn('frames_in_per_second'),
  framesOut('frames_out_per_second'),

  /// Bytes per second.
  dataIn('data_in_per_second'),
  dataOut('data_out_per_second');

  const SysValue(this.key);

  /// The key below `sys`.
  final String key;
}
