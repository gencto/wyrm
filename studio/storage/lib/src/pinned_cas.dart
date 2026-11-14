import 'dart:convert';

import 'base_key_value_storage.dart';

/// A CA trusted for one gateway origin (ADR 0050 §2.3, *Trust*), as it is
/// stored.
final class PinnedCa {
  const PinnedCa({
    required this.origin,
    required this.ca,
    required this.code,
    this.site = '',
    this.connectTo,
  });

  /// `https://host:port`.
  final String origin;

  /// The CA certificate, DER in base64.
  final String ca;

  /// The CA code the person compared (32 hex digits).
  final String code;
  final String site;

  /// The address the origin's name stands for, when it does not resolve.
  final String? connectTo;

  Map<String, Object?> _toMap() => {
    'origin': origin,
    'ca': ca,
    'code': code,
    'site': site,
    'connectTo': ?connectTo,
  };

  static PinnedCa? _of(Object? v) => switch (v) {
    {
      'origin': final String origin,
      'ca': final String ca,
      'code': final String code,
    } =>
      PinnedCa(
        origin: origin,
        ca: ca,
        code: code,
        site: v['site'] is String ? v['site']! as String : '',
        connectTo: v['connectTo'] is String ? v['connectTo']! as String : null,
      ),
    _ => null,
  };
}

/// The pinned CAs, all under one key: a JSON list of [PinnedCa]. A value
/// that does not read is dropped, never half-used.
final class PinnedCas {
  const PinnedCas(this._storage);

  static const key = 'pinnedCas';

  final BaseKeyValueStorage _storage;

  Future<List<PinnedCa>> read() async {
    final text = await _storage.get<String>(key);
    if (text == null) {
      return const [];
    }
    try {
      return [
        for (final v in jsonDecode(text) as List<Object?>) ?PinnedCa._of(v),
      ];
    } on Object {
      return const [];
    }
  }

  Future<void> write(Iterable<PinnedCa> pins) => pins.isEmpty
      ? _storage.delete(key)
      : _storage.put(key, jsonEncode([for (final p in pins) p._toMap()]));
}
