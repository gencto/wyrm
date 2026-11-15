/// Why *It matches · trust `<site>`* pinned nothing (ADR 0050 §2.3,
/// *Trust*): the card says it and stays open.
enum TrustRefusal {
  /// The gateway did not answer the second read.
  noAnswer,

  /// The CA it sends now is not the one whose code was shown.
  changed,

  /// Its `ca_fp` or its TXT `fp` is not the code of its CA.
  mismatch,

  /// Its certificate does not chain to that CA, or does not name the
  /// gateway's host.
  chain,
}
