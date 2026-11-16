// The closed sets of the gateway and the agent link equal their source of
// truth on the Rust side: the literals are read from the Rust files (and
// ADR 0050 for `role`) and compared both ways. Each extraction must find
// something: a Rust refactor that moves a list fails here instead of
// passing with nothing compared.

import 'dart:io';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

final _repo = Directory.current.parent.parent.path;

String _src(String path) => File('$_repo/$path').readAsStringSync();

/// The text from [start] to the first [end] after it, both included.
String _block(String text, String start, String end, {String? what}) {
  final i = text.indexOf(start);
  if (i < 0) fail('${what ?? start}: not found');
  final j = text.indexOf(end, i + start.length);
  if (j < 0) fail('${what ?? start}: no end');
  return text.substring(i, j + end.length);
}

/// Every `"<literal>"` in [text] matched by [re] (group 1).
Set<String> _all(String text, RegExp re, String what) {
  final out = {for (final m in re.allMatches(text)) m.group(1)!};
  if (out.isEmpty) fail('$what: nothing extracted');
  return out;
}

/// The `=> "name"` arms of `fn name(self)` in `impl <ty> {`.
Set<String> _names(String text, String ty) {
  final impl = _block(text, 'impl $ty {', '\n}\n', what: 'impl $ty');
  final f = _block(impl, 'fn name(self)', '\n    }\n', what: '$ty::name');
  return _all(f, RegExp(r'=> "([a-z0-9_]+)"'), '$ty::name');
}

/// The `Variant => "name"` lines of a `name_enum!` enum `ty` (one list of
/// names on the Rust side, `wyrm_core::name_enum!`).
Set<String> _nameEnum(String text, String ty) {
  final e = _block(text, 'enum $ty {', '\n    }\n', what: 'name_enum $ty');
  return _all(e, RegExp(r'=> "([a-z0-9_~]+)"'), 'name_enum $ty');
}

Set<String> _wires(List<WireName> values) => {for (final v in values) v.wire};

void main() {
  group('crates/wyrm-gateway', () {
    final devices = _src('crates/wyrm-gateway/src/devices.rs');
    final http = _src('crates/wyrm-gateway/src/http.rs');
    final ws = _src('crates/wyrm-gateway/src/ws.rs');

    test('DevicePlatform = devices.rs PLATFORMS', () {
      final list = _block(devices, 'pub const PLATFORMS', '];');
      expect(
        _wires(DevicePlatform.values),
        _all(list, RegExp(r'"([a-z]+)"'), 'PLATFORMS'),
      );
    });

    test('DeviceAlg = KeyAlg::name', () {
      expect(_wires(DeviceAlg.values), _names(devices, 'KeyAlg'));
    });

    test('StepUp = StepUp::name', () {
      expect(_wires(StepUp.values), _names(devices, 'StepUp'));
    });

    test('GatewayDeviceState = the states of devices_of', () {
      final f = _block(devices, 'let state = if', '};');
      expect(
        _wires(GatewayDeviceState.values),
        _all(f, RegExp(r'"([a-z_]+)"'), 'device states'),
      );
    });

    test('GatewayRefusal = the codes of From<Refused>', () {
      final f = _block(http, 'impl From<Refused> for ApiError', '\n}\n');
      final codes = {
        ..._all(f, RegExp(r'"([a-z_]+)" =>'), 'Refused::Code arms'),
        ..._all(f, RegExp(r'coded\("([a-z_]+)"'), 'coded(...)'),
      };
      expect(_wires(GatewayRefusal.values), codes);
    });

    test('GatewayRole = ADR 0050 role', () {
      final adr = _src('docs/adr/0050-device-unlock-and-gateway-discovery.md');
      final row = RegExp(r'\| `role` \| `(\w+)` or `(\w+)`').firstMatch(adr);
      expect(row, isNotNull, reason: 'the role row of ADR 0050 moved');
      expect(_wires(GatewayRole.values), {row!.group(1), row.group(2)});
      final info = _block(
        _src('crates/wyrm-gateway/src/lib.rs'),
        'pub fn info(&self)',
        '\n    }\n',
      );
      expect(
        GatewayRole.fromWire(
          RegExp(r'"role"\.to_owned\(\), Value::from\("(\w+)"\)')
                  .firstMatch(info)
                  ?.group(1) ??
              '',
        ),
        isNotNull,
      );
    });

    test('FrameOp = the ops ws.rs serves', () {
      final op = _src('crates/wyrm-gateway/src/ws/op.rs');
      expect(_wires(FrameOp.values), _nameEnum(op, 'OpName'));
    });

    test('FrameEventKind = the event types ws.rs sends', () {
      expect(
        _wires(FrameEventKind.values),
        _all(ws, RegExp(r'event_frame\(\s*id,\s*"([a-z_]+)"'), 'event_frame'),
      );
    });
  });

  group('links/agent', () {
    final lib = _src('links/agent/src/lib.rs');
    final tools = _src('links/agent/src/tools.rs');

    test('AgentTaskState = wire_enum! TaskState (codes and names)', () {
      final e = _block(lib, 'pub enum TaskState {', '\n    }');
      final rust = {
        for (final m in RegExp(r'(\d+) => "([a-z_]+)"').allMatches(e))
          '${m.group(1)}=${m.group(2)}',
      };
      expect(rust, isNotEmpty);
      expect({
        for (final s in AgentTaskState.values) '${s.code}=${s.wire}',
      }, rust);
    });

    test('AgentEventKind = the events of progress()', () {
      expect(
        _wires(AgentEventKind.values),
        _all(
          lib,
          RegExp(r'progress\(\s*sink,\s*id,\s*"([a-z_]+)"'),
          'progress',
        ),
      );
    });

    test('AgentStepStatus = StepStatus::name', () {
      expect(_wires(AgentStepStatus.values), _nameEnum(tools, 'StepStatus'));
    });

    test('AgentStepCheck = Check::name', () {
      expect(_wires(AgentStepCheck.values), _names(tools, 'Check'));
    });

    test('AgentFindingRefusal = Refused::name', () {
      expect(_wires(AgentFindingRefusal.values), _nameEnum(tools, 'Refused'));
    });

    test('AgentStepKind = the keys of run_format', () {
      final f = _block(tools, 'fn run_format(&self)', '\n    }\n');
      expect(
        _wires(AgentStepKind.values),
        _all(
          f,
          RegExp(r'OpKind::\w+ => \{\s*m\.insert\(\s*"([a-z_]+)"'),
          'run_format',
        ),
      );
    });

    test('planUnhashed = UNHASHED', () {
      final c = _block(tools, 'pub const UNHASHED', '];');
      expect(planUnhashed, _all(c, RegExp(r'"([a-z_]+)"'), 'UNHASHED'));
    });
  });
}
