/// Where a grant of `sys ▸ get_permissions` comes from (wyrm-admin
/// `perm_row`): the router's ACL, a gateway role, a link's grant.
enum GrantSource {
  acl('acl'),
  gateway('gateway'),
  link('link');

  const GrantSource(this.wire);

  /// Its name on the wire.
  final String wire;

  /// The source named [wire]; null for one this client does not know.
  static GrantSource? fromWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;
}
