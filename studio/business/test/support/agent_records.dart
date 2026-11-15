import 'package:business/wyrm/decode/agent_task.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/agent_task.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The record (`~state`) of a task as the agent link writes it: [fields],
/// and the fields the link always writes (`links/agent/src/lib.rs`: owner,
/// ask, plan, plan_hash, step, log, tokens) where a test leaves them out.
/// `plan_hash` is the link's hash of the plan, as the link makes it.
Value taskRecord(Map<String, Object?> fields) {
  final plan = Value.from(fields['plan'] ?? const <Object?>[]);
  return Value.from({
    'owner': '',
    'ask': '',
    'plan': const <Object?>[],
    'plan_hash': planHash(plan),
    'step': 0,
    'log': const <Object?>[],
    'tokens': 0,
    ...fields,
  });
}

/// The task [record] decodes to; a record that does not decode fails the
/// test with its field.
AgentTask taskOf(Value record, [String id = 't']) =>
    switch (agentTaskOf(id, record)) {
      Valid(:final value) => value,
      Invalid(:final field, :final reason) => fail('$field: $reason'),
    };
