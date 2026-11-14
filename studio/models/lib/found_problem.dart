/// Why a found gateway cannot be picked (ADR 0050 §2.3; the row shows it
/// greyed out with the reason).
enum FoundProblem {
  /// Plain `http` off loopback (`insecure_plaintext`).
  plainHttp,

  /// No `/api/info`: a wyrmd older than this Studio needs, or not a gateway.
  noInfo,

  /// `/api/info` `min_studio` is newer than this Studio.
  studioTooOld,

  /// The CA code it announced or sent is not the code of its CA.
  codeMismatch,

  /// Its certificate names neither the address nor a DNS name.
  noName,

  /// `/api/info` did not answer.
  noAnswer,

  /// A certificate this computer does not trust and no CA to check.
  noCa,
}
