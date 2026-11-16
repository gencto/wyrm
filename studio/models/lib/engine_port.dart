/// The engine's port names the editor treats in its own way: a block's
/// main value (`in`, `out`), the run trigger and the event and state
/// outputs of a block with behaviours (ADR 0040 §2). Any other port is a
/// name of the catalog.
enum EnginePort {
  in_('in'),
  out('out'),
  trigger('trigger'),
  sent('sent'),
  ok('ok'),
  error('error'),
  lastRun('last_run'),
  right('right'),
  value('value'),
  actions('actions');

  const EnginePort(this.wire);

  /// The port's name in the catalog and the definition.
  final String wire;

  static final Map<String, EnginePort> _byWire = {
    for (final p in values) p.wire: p,
  };

  /// The port named [s]; null for any other name.
  static EnginePort? fromWire(String s) => _byWire[s];
}
