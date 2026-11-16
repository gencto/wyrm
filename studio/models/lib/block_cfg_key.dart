/// The config keys of a flow node that the editor itself reads or tests
/// for (spec 06, docs/flow-blocks.md). Any other key is a parameter the
/// catalog describes, edited by name.
enum BlockCfgKey {
  key('key'),
  keyScope('key_scope'),
  pathScope('path_scope'),
  path('path'),
  target('target'),
  node('node'),
  action('action'),
  on('on'),
  args('args'),
  allowBad('allow_bad'),
  operandValues('values'),
  defaults('defaults'),
  descriptions('descriptions'),
  enabled('enabled'),
  inputs('inputs'),
  outputs('outputs'),
  value('value'),
  intervalMs('interval_ms'),
  autoRun('auto_run'),
  runOnStart('run_on_start'),
  timeZone('time_zone'),
  mapping('mapping'),
  aggregates('aggregates'),
  method('method'),
  delimiter('delimiter'),
  withHeader('with_header');

  const BlockCfgKey(this.wire);

  /// The key as the definition writes it.
  final String wire;

  static final Map<String, BlockCfgKey> _byWire = {
    for (final k in values) k.wire: k,
  };

  /// The key named [s]; null for a key the editor does not read itself.
  static BlockCfgKey? fromWire(String s) => _byWire[s];
}
