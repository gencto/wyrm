/// A byte count as a person reads it: `812 B`, `48 KiB`, `3.1 MiB`,
/// `1.2 GiB`.
String bytesText(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KiB', 'MiB', 'GiB', 'TiB'];
  var v = bytes / 1024;
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final whole = v >= 100 || v == v.roundToDouble();
  return '${whole ? v.round() : v.toStringAsFixed(1)} ${units[u]}';
}
