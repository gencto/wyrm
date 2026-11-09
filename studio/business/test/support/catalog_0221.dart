// The catalog as the demo's broker answers `dataflows` ▸ `node_types` with
// spec 06 0.2.21 (2026-11-09, branch broker/flow-preview): the types the
// operand and case tests read, descriptions left out.

import 'dart:convert';

List<Map<String, Object?>> catalog0221() => [
  for (final t in jsonDecode(_json) as List<Object?>)
    t! as Map<String, Object?>,
];

const _json = '''
[
  {
    "category": "Math",
    "echo_inputs": true,
    "inputs": [
      "in",
      "in.k",
      "in.b",
      "in.input_min",
      "in.input_max",
      "in.output_min",
      "in.output_max"
    ],
    "outputs": [
      "out",
      "input_out_of_range"
    ],
    "params": [
      {
        "default": 1,
        "echo": true,
        "name": "k",
        "port": "in.k",
        "required": false,
        "type": "number"
      },
      {
        "default": 0,
        "echo": true,
        "name": "b",
        "port": "in.b",
        "required": false,
        "type": "number"
      },
      {
        "default": 0,
        "echo": true,
        "name": "input_min",
        "port": "in.input_min",
        "required": false,
        "type": "number"
      },
      {
        "default": 1,
        "echo": true,
        "name": "input_max",
        "port": "in.input_max",
        "required": false,
        "type": "number"
      },
      {
        "default": 0,
        "echo": true,
        "name": "output_min",
        "port": "in.output_min",
        "required": false,
        "type": "number"
      },
      {
        "default": 100,
        "echo": true,
        "name": "output_max",
        "port": "in.output_max",
        "required": false,
        "type": "number"
      }
    ],
    "port_types": {
      "b": "number",
      "in": "number",
      "in.b": "number",
      "in.input_max": "number",
      "in.input_min": "number",
      "in.k": "number",
      "in.output_max": "number",
      "in.output_min": "number",
      "input_max": "number",
      "input_min": "number",
      "input_out_of_range": "bool",
      "k": "number",
      "out": "number",
      "output_max": "number",
      "output_min": "number"
    },
    "type": "scale"
  },
  {
    "category": "Variables",
    "echo_inputs": true,
    "inputs": [
      "in"
    ],
    "outputs": [
      "out"
    ],
    "params": [
      {
        "default": 0,
        "echo": true,
        "name": "value",
        "required": false,
        "type": "number"
      }
    ],
    "port_types": {
      "in": "any",
      "out": "number",
      "value": "number"
    },
    "type": "number"
  },
  {
    "category": "Math",
    "dyn_inputs": {
      "default": [
        "0",
        "1"
      ],
      "param": "inputs",
      "prefix": "in."
    },
    "echo_inputs": true,
    "inputs": [],
    "outputs": [
      "out"
    ],
    "params": [
      {
        "default": [
          "0",
          "1"
        ],
        "echo": true,
        "name": "inputs",
        "required": false,
        "type": "array"
      }
    ],
    "port_types": {
      "in.0": "any",
      "in.1": "any",
      "inputs": "any",
      "out": "number"
    },
    "type": "add",
    "values": true
  },
  {
    "category": "Math",
    "echo_inputs": true,
    "inputs": [
      "in",
      "in.precision",
      "in.min_precision"
    ],
    "outputs": [
      "out",
      "text"
    ],
    "params": [
      {
        "default": 0,
        "echo": true,
        "name": "precision",
        "port": "in.precision",
        "required": false,
        "type": "number"
      },
      {
        "echo": true,
        "name": "min_precision",
        "port": "in.min_precision",
        "required": false,
        "type": "number"
      }
    ],
    "port_types": {
      "in": "any",
      "in.min_precision": "any",
      "in.precision": "any",
      "min_precision": "number",
      "out": "number",
      "precision": "number",
      "text": "any"
    },
    "type": "round",
    "values": true
  },
  {
    "category": "Logic",
    "dyn_inputs": {
      "default": [
        "0",
        "1"
      ],
      "param": "inputs",
      "prefix": "in."
    },
    "echo_inputs": true,
    "inputs": [
      "in.op",
      "in.then",
      "in.else"
    ],
    "outputs": [
      "out"
    ],
    "params": [
      {
        "choices": [
          "=",
          "!=",
          "and",
          "or",
          ">",
          "<",
          ">=",
          "<=",
          "contains",
          "starts_with",
          "ends_with"
        ],
        "default": "=",
        "echo": true,
        "name": "op",
        "port": "in.op",
        "required": false,
        "type": "string"
      },
      {
        "default": true,
        "echo": true,
        "name": "then",
        "port": "in.then",
        "required": false,
        "type": "dynamic"
      },
      {
        "default": false,
        "echo": true,
        "name": "else",
        "port": "in.else",
        "required": false,
        "type": "dynamic"
      },
      {
        "default": [
          "0",
          "1"
        ],
        "echo": true,
        "name": "inputs",
        "required": false,
        "type": "array"
      }
    ],
    "port_types": {
      "else": "any",
      "in.0": "any",
      "in.1": "any",
      "in.else": "any",
      "in.op": "any",
      "in.then": "any",
      "inputs": "any",
      "op": "any",
      "out": "any",
      "then": "any"
    },
    "type": "if",
    "values": true
  },
  {
    "category": "Logic",
    "echo_inputs": true,
    "inputs": [
      "reset",
      "in.enabled",
      "in.interval",
      "in.step",
      "in.modulo",
      "in.loop",
      "in.reset_value"
    ],
    "outputs": [
      "out",
      "on_loop"
    ],
    "params": [
      {
        "default": false,
        "echo": true,
        "name": "enabled",
        "port": "in.enabled",
        "required": false,
        "type": "bool"
      },
      {
        "default": 0.5,
        "echo": true,
        "editor": "duration",
        "name": "interval",
        "port": "in.interval",
        "required": false,
        "type": "number"
      },
      {
        "default": 1,
        "echo": true,
        "name": "step",
        "port": "in.step",
        "required": false,
        "type": "number"
      },
      {
        "default": 0,
        "echo": true,
        "name": "modulo",
        "port": "in.modulo",
        "required": false,
        "type": "number"
      },
      {
        "default": true,
        "echo": true,
        "name": "loop",
        "port": "in.loop",
        "required": false,
        "type": "bool"
      },
      {
        "default": 0,
        "echo": true,
        "name": "reset_value",
        "port": "in.reset_value",
        "required": false,
        "type": "number"
      }
    ],
    "port_types": {
      "enabled": "bool",
      "in.enabled": "any",
      "in.interval": "any",
      "in.loop": "any",
      "in.modulo": "any",
      "in.reset_value": "any",
      "in.step": "any",
      "interval": "number",
      "loop": "bool",
      "modulo": "number",
      "on_loop": "map",
      "out": "number",
      "reset": "any",
      "reset_value": "number",
      "step": "number"
    },
    "type": "stopwatch"
  },
  {
    "category": "Text",
    "dyn_inputs": {
      "default": [
        "0",
        "1"
      ],
      "param": "inputs",
      "prefix": "in."
    },
    "echo_inputs": true,
    "inputs": [
      "in.strict"
    ],
    "outputs": [
      "out"
    ],
    "params": [
      {
        "default": false,
        "echo": true,
        "name": "strict",
        "port": "in.strict",
        "required": false,
        "type": "bool"
      },
      {
        "default": [
          "0",
          "1"
        ],
        "echo": true,
        "name": "inputs",
        "required": false,
        "type": "array"
      }
    ],
    "port_types": {
      "in.0": "any",
      "in.1": "any",
      "in.strict": "any",
      "inputs": "any",
      "out": "any",
      "strict": "bool"
    },
    "type": "concat",
    "values": true
  },
  {
    "category": "Logic",
    "dyn_inputs": {
      "default": [
        "0",
        "1"
      ],
      "param": "inputs",
      "prefix": "in."
    },
    "echo_inputs": true,
    "inputs": [
      "in",
      "in.op",
      "in.else"
    ],
    "outputs": [
      "out"
    ],
    "params": [
      {
        "choices": [
          "=",
          "!=",
          ">",
          "<",
          ">=",
          "<=",
          "contains",
          "starts_with",
          "ends_with"
        ],
        "default": "=",
        "echo": true,
        "name": "op",
        "port": "in.op",
        "required": false,
        "type": "string"
      },
      {
        "echo": true,
        "name": "else",
        "port": "in.else",
        "required": false,
        "type": "dynamic"
      },
      {
        "default": [
          "0",
          "1"
        ],
        "echo": true,
        "name": "inputs",
        "required": false,
        "type": "array"
      }
    ],
    "port_types": {
      "else": "any",
      "in": "any",
      "in.0": "any",
      "in.1": "any",
      "in.else": "any",
      "in.op": "any",
      "inputs": "any",
      "op": "any",
      "out": "any"
    },
    "type": "case",
    "values": true
  }
]
''';
