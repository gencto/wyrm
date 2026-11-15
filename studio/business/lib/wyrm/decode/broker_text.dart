import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

/// A text value of a broker read once ([field] of [shape], such as
/// `sys/version`): its text; none when the broker sent none; [Invalid] when
/// it is not a text.
Decoded<String?> brokerTextOf(Value? v, String shape, String field) =>
    switch (v) {
      null || VNull() => const Valid(null),
      VStr(:final v) => Valid(v),
      _ => Invalid(shape, field, 'not a text'),
    };

/// The host of a broker (`linux-aarch64`) from its `sys/distribution`, when
/// that names one; the brokers of today name their build there
/// (`rust (prod)`), not the host.
String? hostOf(String? distribution) =>
    distribution != null &&
        RegExp('^(linux|macos|windows)-').hasMatch(distribution)
    ? distribution
    : null;
