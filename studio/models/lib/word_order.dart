/// The word and byte order a modbus data type's suffix sets
/// (docs/modbus.md): none, `_wswap`, `_bswap`, `_wbswap`.
enum WordOrder {
  abcd,
  cdab,
  badc,
  dcba;

  /// The order of the data type [dtype] (`f32_wswap` → [cdab]).
  static WordOrder of(String dtype) => switch (dtype) {
    final d when d.endsWith('_wbswap') => dcba,
    final d when d.endsWith('_wswap') => cdab,
    final d when d.endsWith('_bswap') => badc,
    _ => abcd,
  };
}
