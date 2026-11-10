// The catalog as a broker with ADR 0040 answers `dataflows` ▸ `node_types`
// (spec 06 0.2.22–0.2.26, branch broker/flow-behaviours,
// `crates/wyrm-flow/src/catalog.rs`): the types the wave-2 tests read. A
// parameter has `port` when the type lists `in.<name>`, `scope` when
// another parameter holds its scope; `invoke` says `dyn_inputs.keys`, and
// `invoke` and `set` say `trigger`.

Map<String, Object?> _p(
  String name,
  String type, {
  bool required = false,
  Object? def,
  List<String>? choices,
  String? port,
  String? scope,
  bool echo = true,
  String description = '',
}) => {
  'name': name,
  'type': type,
  'required': required,
  'description': description,
  'default': ?def,
  'choices': ?choices,
  'port': ?port,
  'scope': ?scope,
  'echo': echo,
};

final Map<String, Object?> _key = _p(
  'key',
  'string',
  required: true,
  port: 'in.key',
  scope: 'key_scope',
);
final Map<String, Object?> _keyScope = _p('key_scope', 'string');
final Map<String, Object?> _interval = _p(
  'interval_ms',
  'number',
  def: 0,
  port: 'in.interval_ms',
);
final Map<String, Object?> _enabled = _p(
  'enabled',
  'bool',
  def: true,
  port: 'in.enabled',
);
final Map<String, Object?> _runOnStart = _p(
  'run_on_start',
  'bool',
  def: false,
  description:
      'WARNING: true runs this command once every time the flow starts: at '
      'each deploy, hot swap, reload and broker restart (default false: a '
      'start never runs a command).',
);
Map<String, Object?> _autoRun({required bool def}) =>
    _p('auto_run', 'bool', def: def, port: 'in.auto_run');

/// The types of ADR 0040 the tests use, as plain maps.
List<Map<String, Object?>> catalog0226() => [
  {
    'type': 'subscribe',
    'category': 'Sources',
    'description': 'Values of a point as they change.',
    'inputs': ['in.key'],
    'outputs': ['out', 'error'],
    'params': [_key, _keyScope],
    'port_types': {'in.key': 'any', 'out': 'any', 'error': 'any'},
  },
  {
    'type': 'liveliness',
    'category': 'Sources',
    'description': 'Whether a node is alive.',
    'inputs': ['in.key'],
    'outputs': ['out', 'error'],
    'params': [_key, _keyScope],
    'port_types': {'in.key': 'any', 'out': 'bool', 'error': 'any'},
  },
  {
    'type': 'load_value',
    'category': 'Sources',
    'description': "One read of a point's value.",
    'inputs': [
      'trigger',
      'in.key',
      'in.interval_ms',
      'in.auto_run',
      'in.enabled',
    ],
    'outputs': ['out', 'ok', 'error', 'running', 'last_run'],
    'params': [_key, _keyScope, _interval, _autoRun(def: true), _enabled],
    'echo_inputs': true,
    'port_types': {'running': 'bool', 'last_run': 'number'},
  },
  {
    'type': 'list_children',
    'category': 'Sources',
    'description': 'The children of a node as a list of rows.',
    'inputs': [
      'trigger',
      'in.path',
      'in.interval_ms',
      'in.auto_run',
      'in.enabled',
    ],
    'outputs': ['out', 'ok', 'error', 'running', 'last_run'],
    'params': [
      _p(
        'path',
        'string',
        required: true,
        port: 'in.path',
        scope: 'path_scope',
      ),
      _p('path_scope', 'string'),
      _interval,
      _autoRun(def: true),
      _enabled,
    ],
    'echo_inputs': true,
    'port_types': {'running': 'bool', 'last_run': 'number'},
  },
  {
    'type': 'set',
    'category': 'Outputs',
    'description': 'Writes in to a point.',
    'inputs': ['in', 'trigger', 'in.interval_ms', 'in.auto_run', 'in.enabled'],
    'outputs': ['sent', 'ok', 'error', 'running', 'last_run'],
    'params': [
      _p('path', 'string', required: true),
      _p('on', 'string', def: 'change', choices: ['change', 'any']),
      _p('deadband', 'number', def: 0),
      _p('allow_bad', 'bool', def: false),
      _interval,
      _autoRun(def: true),
      _enabled,
      _runOnStart,
    ],
    'echo_inputs': true,
    'trigger': true,
    'port_types': {'running': 'bool', 'last_run': 'number'},
  },
  {
    'type': 'invoke',
    'category': 'Outputs',
    'description': 'The action block: runs an action of a node.',
    'inputs': ['in', 'trigger', 'in.interval_ms', 'in.auto_run', 'in.enabled'],
    'outputs': ['out', 'result', 'sent', 'ok', 'error', 'running', 'last_run'],
    'dyn_inputs': {
      'param': 'args',
      'prefix': 'arg.',
      'default': <String>[],
      'keys': true,
    },
    'params': [
      _p('path', 'string', required: true),
      _p('action', 'string', required: true),
      _p('args', 'map'),
      _p(
        'on',
        'string',
        def: 'any',
        choices: ['any', 'rising', 'falling', 'change'],
      ),
      _p('allow_bad', 'bool', def: false),
      _interval,
      _autoRun(def: false),
      _enabled,
      _runOnStart,
    ],
    'echo_inputs': true,
    'trigger': true,
    'port_types': {'running': 'bool', 'last_run': 'number'},
  },
  {
    'type': 'publish',
    'category': 'Outputs',
    'description': 'Publishes in as a value of this flow.',
    'inputs': ['in'],
    'outputs': <String>[],
    'params': [
      _p('node', 'string', required: true),
      _p('meta', 'map'),
    ],
    'echo_inputs': true,
    'port_types': {'in': 'any'},
  },
  {
    'type': 'string',
    'category': 'Variables',
    'description': 'A text.',
    'inputs': ['in'],
    'outputs': ['out'],
    'params': [_p('value', 'string')],
    'echo_inputs': true,
    'port_types': {'in': 'any', 'out': 'any'},
  },
  {
    'type': 'concat',
    'category': 'Text',
    'description': 'Its inputs as one text.',
    'inputs': ['in.strict'],
    'outputs': ['out'],
    'dyn_inputs': {
      'param': 'inputs',
      'prefix': 'in.',
      'default': ['0', '1'],
    },
    'params': [
      _p('inputs', 'array', def: ['0', '1'], echo: false),
      _p('strict', 'bool', def: false, port: 'in.strict'),
    ],
    'echo_inputs': true,
    'values': true,
    'port_types': {'out': 'any'},
  },
  {
    'type': 'add',
    'category': 'Math',
    'description': 'The sum of its inputs.',
    'inputs': <String>[],
    'outputs': ['out'],
    'dyn_inputs': {
      'param': 'inputs',
      'prefix': 'in.',
      'default': ['0', '1'],
    },
    'params': [
      _p('inputs', 'array', def: ['0', '1'], echo: false),
    ],
    'echo_inputs': true,
    'values': true,
    'port_types': {'out': 'number'},
  },
  {
    'type': 'divide',
    'category': 'Math',
    'description': 'The first input divided by the others.',
    'inputs': <String>[],
    'outputs': ['out'],
    'dyn_inputs': {
      'param': 'inputs',
      'prefix': 'in.',
      'default': ['0', '1'],
    },
    'params': [
      _p('inputs', 'array', def: ['0', '1'], echo: false),
    ],
    'echo_inputs': true,
    'values': true,
    'port_types': {'out': 'number'},
  },
  {
    'type': 'rising_edge',
    'category': 'Logic',
    'description': 'An event when in becomes true.',
    'inputs': ['in'],
    'outputs': ['on_edge'],
    'params': <Object>[],
    'echo_inputs': true,
    'port_types': {'in': 'any', 'on_edge': 'any'},
  },
  {
    'type': 'make_object',
    'category': 'Data',
    'description': 'A map of its named inputs.',
    'inputs': <String>[],
    'outputs': ['out'],
    'dyn_inputs': {
      'param': 'inputs',
      'prefix': 'in.',
      'default': ['a', 'b'],
    },
    'params': [
      _p('inputs', 'array', def: ['a', 'b'], echo: false),
    ],
    'echo_inputs': true,
    'values': true,
    'port_types': {'out': 'map'},
  },
  {
    'type': 'stats',
    'category': 'Data',
    'description': "A list's numbers.",
    'inputs': ['in'],
    'outputs': ['min', 'max', 'avg', 'sum', 'count'],
    'params': <Object>[],
    'echo_inputs': true,
    'port_types': {'count': 'number'},
  },
  {
    'type': 'debounce',
    'category': 'Time',
    'description': 'The last value after a quiet time.',
    'inputs': ['in', 'in.ms'],
    'outputs': ['out'],
    'params': [_p('ms', 'number', def: 500, port: 'in.ms')],
    'echo_inputs': true,
    'port_types': {'out': 'any'},
  },
];
