/// Parts of Studio whose broker side does not exist yet. Their screens and
/// state are built and tested; every way into them is behind the flag, so
/// nothing is shown disabled with a promise (`docs/design/specs/
/// updates-backups.md`, *Order of work*).
abstract final class Features {
  /// Updating the broker itself (ADR 0048 §2): `sys` values `latest`,
  /// `update_available`, `update_state`, `update_last`, attribute
  /// `update_mode`, actions `update` and `rollback_update`. Off until
  /// `wyrmd` has them.
  static const brokerUpdate = false;
}
