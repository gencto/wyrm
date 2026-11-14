import 'dart:convert';

import 'base_key_value_storage.dart';

/// What Studio keeps of one gateway user on this computer (ADR 0050 §1,
/// unlock-discover.md §5): which device key is theirs, and their choices.
/// Never a secret: the private key stays in the OS store, under [alias].
final class DeviceRecord {
  const DeviceRecord({
    this.site = '',
    this.deviceId,
    this.alias,
    this.added = 0,
    this.lastUsed = 0,
    this.stale = false,
    this.offered = false,
    this.dontAsk = false,
    this.lockAfter = 0,
  });

  /// The gateway's site (it is in every message the key signs).
  final String site;

  /// The gateway's id of the device record (`POST /api/devices`).
  final String? deviceId;

  /// The name of the key in the OS store.
  final String? alias;

  /// When the key was made and last used, seconds since the Unix epoch.
  final int added;
  final int lastUsed;

  /// The key is gone (fingerprints changed, the gateway refused it): the
  /// gateway's record is removed after the next password login.
  final bool stale;

  /// The offer was shown once; `Don't ask on this computer` was chosen.
  final bool offered;
  final bool dontAsk;

  /// The idle lock delay in minutes; 0 is off.
  final int lockAfter;

  /// A key that can sign: made, registered and not stale.
  bool get usable => deviceId != null && alias != null && !stale;

  DeviceRecord copyWith({
    String? site,
    String? Function()? deviceId,
    String? Function()? alias,
    int? added,
    int? lastUsed,
    bool? stale,
    bool? offered,
    bool? dontAsk,
    int? lockAfter,
  }) => DeviceRecord(
    site: site ?? this.site,
    deviceId: deviceId == null ? this.deviceId : deviceId(),
    alias: alias == null ? this.alias : alias(),
    added: added ?? this.added,
    lastUsed: lastUsed ?? this.lastUsed,
    stale: stale ?? this.stale,
    offered: offered ?? this.offered,
    dontAsk: dontAsk ?? this.dontAsk,
    lockAfter: lockAfter ?? this.lockAfter,
  );

  Map<String, Object?> _toMap() => {
    if (site.isNotEmpty) 'site': site,
    'deviceId': ?deviceId,
    'alias': ?alias,
    if (added > 0) 'added': added,
    if (lastUsed > 0) 'lastUsed': lastUsed,
    if (stale) 'stale': true,
    if (offered) 'offered': true,
    if (dontAsk) 'dontAsk': true,
    if (lockAfter > 0) 'lockAfter': lockAfter,
  };

  static DeviceRecord? _of(Object? v) {
    if (v is! Map<String, Object?>) {
      return null;
    }
    String? s(String k) => v[k] is String ? v[k]! as String : null;
    int n(String k) => v[k] is int ? v[k]! as int : 0;
    bool b(String k) => v[k] == true;
    return DeviceRecord(
      site: s('site') ?? '',
      deviceId: s('deviceId'),
      alias: s('alias'),
      added: n('added'),
      lastUsed: n('lastUsed'),
      stale: b('stale'),
      offered: b('offered'),
      dontAsk: b('dontAsk'),
      lockAfter: n('lockAfter'),
    );
  }
}

/// The [DeviceRecord]s of this computer, one per gateway origin and user,
/// all under one key: a JSON map `<origin>|<user>` → record. A value that
/// does not read is dropped, never half-used.
final class DeviceRecords {
  const DeviceRecords(this._storage);

  static const key = 'deviceRecords';

  /// `UnlockLinux` was shown: Studio says it once on this computer.
  static const noticedKey = 'deviceUnlockNoticed';

  final BaseKeyValueStorage _storage;

  /// The key of [origin] and [user] in the map.
  static String id(String origin, String user) => '$origin|$user';

  Future<Map<String, DeviceRecord>> _all() async {
    final text = await _storage.get<String>(key);
    if (text == null) {
      return {};
    }
    try {
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(text) as Map<String, Object?>).entries)
          if (DeviceRecord._of(value) case final r?) key: r,
      };
    } on Object {
      return {};
    }
  }

  /// The record of [origin] and [user], or an empty one.
  Future<DeviceRecord> read(String origin, String user) async =>
      (await _all())[id(origin, user)] ?? const DeviceRecord();

  /// Keeps [record] for [origin] and [user]; an empty one is deleted.
  Future<void> write(String origin, String user, DeviceRecord record) async {
    final all = await _all();
    final map = record._toMap();
    if (map.isEmpty) {
      all.remove(id(origin, user));
    } else {
      all[id(origin, user)] = record;
    }
    await (all.isEmpty
        ? _storage.delete(key)
        : _storage.put(
            key,
            jsonEncode({
              for (final MapEntry(:key, :value) in all.entries)
                key: value._toMap(),
            }),
          ));
  }

  Future<bool> noticed() async => await _storage.get<bool>(noticedKey) ?? false;

  Future<void> markNoticed() => _storage.put(noticedKey, true);
}
