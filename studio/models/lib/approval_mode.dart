import 'package:wyrm_core/wyrm_core.dart' show WireName, wireByName;

/// Who approves an agent plan (the agent link's `require_approval`).
enum ApprovalMode implements WireName {
  /// A person approves every step that changes something.
  write('write'),

  /// `write` steps run with the agent's own key; `config` steps wait.
  config('config'),

  /// Like [config]: the link still asks a person for every `config` step.
  never('never');

  const ApprovalMode(this.wire);

  /// The param's value on the wire (`sys/links/<id>` ▸ `update {params}`).
  @override
  final String wire;

  /// A pick of a plan's suggestion may then write without a person
  /// (docs/agent.md, AI-4).
  bool get unattended => this != write;

  static ApprovalMode? fromWire(String s) => wireByName(values, s);
}
