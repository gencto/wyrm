/// The word and byte order a modbus data type's suffix sets
/// (docs/modbus.md): none, `_wswap`, `_bswap`, `_wbswap`.
enum WordOrder {
  abcd,
  cdab,
  badc,
  dcba,
}
