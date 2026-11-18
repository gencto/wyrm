import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/access_tab.dart';
import 'package:models/action_answer.dart';
import 'package:models/agent_config.dart';
import 'package:models/agent_task.dart';
import 'package:models/answer_fault.dart';
import 'package:models/approval_mode.dart';
import 'package:models/approval_refusal.dart';
import 'package:models/assistant_panel.dart';
import 'package:models/attention_item.dart';
import 'package:models/attention_kind.dart';
import 'package:models/audit_entry.dart';
import 'package:models/audit_line.dart';
import 'package:models/backup_job.dart';
import 'package:models/block_info.dart';
import 'package:models/broker_self_update.dart';
import 'package:models/ca_pin.dart';
import 'package:models/call_refusal.dart';
import 'package:models/catalog_category.dart';
import 'package:models/catalog_item.dart';
import 'package:models/change_side.dart';
import 'package:models/explorer_tab.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_frame.dart';
import 'package:models/flow_problem.dart';
import 'package:models/flow_summary.dart';
import 'package:models/found_gateway.dart';
import 'package:models/grant.dart';
import 'package:models/grant_source.dart';
import 'package:models/hist_detail.dart';
import 'package:models/hist_point.dart';
import 'package:models/hist_window.dart';
import 'package:models/history_call.dart';
import 'package:models/history_range.dart';
import 'package:models/install_block.dart';
import 'package:models/install_field.dart';
import 'package:models/install_name_problem.dart';
import 'package:models/install_path.dart';
import 'package:models/install_phase.dart';
import 'package:models/install_source.dart';
import 'package:models/install_step.dart';
import 'package:models/install_target.dart';
import 'package:models/key_kind.dart';
import 'package:models/library_off.dart';
import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/link_origin.dart';
import 'package:models/link_revision.dart';
import 'package:models/link_state.dart';
import 'package:models/links_tab.dart';
import 'package:models/live_set.dart';
import 'package:models/live_value.dart';
import 'package:models/lock_error.dart';
import 'package:models/log_level.dart';
import 'package:models/log_line.dart';
import 'package:models/log_read_error.dart';
import 'package:models/login_failure.dart';
import 'package:models/node_detail.dart';
import 'package:models/node_info.dart';
import 'package:models/node_type.dart';
import 'package:models/package_check.dart';
import 'package:models/package_check_result.dart';
import 'package:models/package_info.dart';
import 'package:models/package_method.dart';
import 'package:models/palette_tab.dart';
import 'package:models/panel_slot.dart';
import 'package:models/param_spec.dart';
import 'package:models/peer.dart';
import 'package:models/peer_kind.dart';
import 'package:models/plan_step.dart';
import 'package:models/profile_info.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:models/requested_right.dart';
import 'package:models/restore_check.dart';
import 'package:models/restore_point.dart';
import 'package:models/role_grant.dart';
import 'package:models/send_link.dart';
import 'package:models/site_choice.dart';
import 'package:models/site_pick.dart';
import 'package:models/staged_change.dart';
import 'package:models/standby_state.dart';
import 'package:models/step_up_request.dart';
import 'package:models/studio_error.dart';
import 'package:models/studio_notice.dart';
import 'package:models/sys_status.dart';
import 'package:models/sys_value.dart';
import 'package:models/system_tab.dart';
import 'package:models/task_event.dart';
import 'package:models/task_event_kind.dart';
import 'package:models/task_finding.dart';
import 'package:models/task_state.dart';
import 'package:models/task_suggestion.dart';
import 'package:models/traffic_measure.dart';
import 'package:models/traffic_sample.dart';
import 'package:models/trend_range.dart';
import 'package:models/trust_refusal.dart';
import 'package:models/undo_tag.dart';
import 'package:models/unlock_fallback.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:models/update_view.dart';
import 'package:models/user_info.dart';
import 'package:models/watch_group.dart';
import 'package:models/workspace.dart';
import 'package:wyrm_client/wyrm_client.dart'
    show DevicePolicy, GatewayDevice, Perm, Status, StepUp;

import '../wyrm/approval.dart';
import '../wyrm/assistant_view.dart';
import '../wyrm/catalog.dart';
import '../wyrm/context_keys.dart';
import '../wyrm/decode/agent_params.dart';
import '../wyrm/decode/backup_job.dart';
import '../wyrm/decode/broker_self_update.dart';
import '../wyrm/decode/live_values.dart';
import '../wyrm/decode/package_info.dart';
import '../wyrm/decode/sys_status.dart';
import '../wyrm/device_keys.dart';
import '../wyrm/discovery.dart' show RangeFault, codeGroups;
import '../wyrm/explorer.dart';
import '../wyrm/features.dart';
import '../wyrm/flow_view/flow_view.dart';
import '../wyrm/gateway_label.dart';
import '../wyrm/historian_stats.dart';
import '../wyrm/history_steps.dart';
import '../wyrm/history_trend.dart';
import '../wyrm/holds.dart';
import '../wyrm/keys.dart';
import '../wyrm/link_update.dart';
import '../wyrm/log_in_page.dart';
import '../wyrm/mappers/agent_task_mapper.dart';
import '../wyrm/mappers/flow_blocks.dart';
import '../wyrm/mappers/live_overlay_mapper.dart';
import '../wyrm/mappers/log_line_mapper.dart';
import '../wyrm/rights.dart';
import '../wyrm/session.dart';
import '../wyrm/shell.dart';
import '../wyrm/sites.dart';
import '../wyrm/task_facts.dart';
import '../wyrm/trend_window.dart';
import 'access/actions/retrieve_access_action.dart';
import 'app_state.dart';
import 'assistant/actions/ask_agent_action.dart';
import 'assistant/actions/retrieve_agent_action.dart';
import 'backups/actions/retrieve_backups_action.dart';
import 'broker_update/actions/update_broker_action.dart';
import 'changes/actions/apply_changes_action.dart';
import 'common/action.dart';
import 'device/actions/enable_device_action.dart';
import 'device/actions/load_device_action.dart';
import 'device/actions/set_device_unlock_action.dart';
import 'device/actions/unlock_with_device_action.dart';
import 'device/actions/unlock_with_password_action.dart';
import 'discovery/actions/trust_gateway_action.dart';
import 'flow_editor/actions/deploy_flow_action.dart';
import 'flows/actions/retrieve_flows_action.dart';
import 'historian/actions/load_trend_window_action.dart';
import 'historian/actions/retrieve_historian_action.dart';
import 'historian/actions/retrieve_series_action.dart';
import 'last_result.dart';
import 'link_install/actions/install_link_action.dart';
import 'links/actions/deauthorize_link_action.dart';
import 'links/actions/get_link_log_action.dart';
import 'links/actions/grant_link_action.dart';
import 'links/actions/remove_link_action.dart';
import 'links/actions/retrieve_link_history_action.dart';
import 'links/actions/retrieve_links_action.dart';
import 'links/actions/rollback_link_params_action.dart';
import 'links/actions/start_link_action.dart';
import 'links/actions/stop_link_action.dart';
import 'login/actions/log_in_action.dart';
import 'login/actions/probe_gateway_action.dart';
import 'nodes/actions/open_node_menu_action.dart';
import 'nodes/actions/retrieve_history_action.dart';
import 'nodes/actions/retrieve_node_detail_action.dart';
import 'nodes/actions/retrieve_nodes_action.dart';
import 'packages/actions/retrieve_packages_action.dart';
import 'peers/actions/retrieve_peers_action.dart';
import 'quarantine/actions/retrieve_quarantine_action.dart';
import 'session/actions/log_out_action.dart';
import 'site/actions/retrieve_sites_action.dart';
import 'system/actions/clear_conns_action.dart';
import 'system/actions/put_profile_action.dart';
import 'system/actions/remove_profile_action.dart';
import 'system/actions/retrieve_profiles_action.dart';
import 'system/actions/retrieve_system_log_action.dart';
import 'tasks/actions/answer_task_action.dart';
import 'tasks/actions/approve_task_action.dart';
import 'tasks/actions/retrieve_tasks_action.dart';
import 'updates/actions/rollback_package_action.dart';
import 'updates/actions/update_package_action.dart';

/// The facade: mix it in and every substate's selectors are in scope.
///
/// `Action` mixes it in, and so does every connector's `_Factory` — which is
/// the whole surface. A reducer reads `login.email`; nothing has to go through
/// a root type and a hop to get there.
mixin Selectors {
  AppState get state;

  SelectConnectivity get connectivity => SelectConnectivity(state);
  SelectLogin get login => SelectLogin(state);
  SelectSession get session => SelectSession(state);
  SelectTheme get theme => SelectTheme(state);
  SelectLanguage get language => SelectLanguage(state);
  SelectSite get site => SelectSite(state);
  SelectNodes get nodes => SelectNodes(state);
  SelectLive get live => SelectLive(state);
  SelectLinks get links => SelectLinks(state);
  SelectQuarantine get quarantine => SelectQuarantine(state);
  SelectPackages get packages => SelectPackages(state);
  SelectLinkInstall get linkInstall => SelectLinkInstall(state);
  SelectPeers get peers => SelectPeers(state);
  SelectFlows get flows => SelectFlows(state);
  SelectFlowEditor get flowEditor => SelectFlowEditor(state);
  SelectTasks get tasks => SelectTasks(state);
  SelectAssistant get assistant => SelectAssistant(state);
  SelectChanges get changes => SelectChanges(state);
  SelectHistorian get historian => SelectHistorian(state);
  SelectAccess get access => SelectAccess(state);
  SelectSystem get system => SelectSystem(state);
  SelectPanels get panels => SelectPanels(state);
  SelectWindow get window => SelectWindow(state);
  SelectProblems get problems => SelectProblems(state);
  SelectUpdates get updates => SelectUpdates(state);
  SelectBackups get backups => SelectBackups(state);
  SelectBrokerUpdate get brokerUpdate => SelectBrokerUpdate(state);
  SelectDevice get device => SelectDevice(state);
  SelectDiscovery get discovery => SelectDiscovery(state);
  SelectClock get clock => SelectClock(state);
}

/// The approval of a task as the logged-in user may give it.
extension TaskApproval on Selectors {
  /// The user decides for [t]: its asker, or `config` on its `approve`.
  /// The link takes the level of the token on
  /// `<agent>/tasks/<id>/~act/approve` (first match, [SelectSite.levelOn]),
  /// not the highest grant on the link.
  bool decidesFor(AgentTask t) {
    final agent = assistant.agent;
    return askedByUser(t) ||
        (agent != null &&
            site.levelOn('$agent/tasks/${t.id}/~act/approve') >= Perm.config);
  }

  /// The user may send a follow-up of [t] (`ask {parent}`, ADR 0049 §9):
  /// its asker, or `config` on the agent's `ask` (the level the link reads
  /// from the token, first match).
  bool mayFollow(AgentTask t) {
    final agent = assistant.agent;
    return askedByUser(t) ||
        (agent != null && site.levelOn('$agent/~act/ask') >= Perm.config);
  }

  /// The logged-in user asked [t] (the record's owner is `user:<name>`).
  bool askedByUser(AgentTask t) =>
      t.owner.isNotEmpty &&
      (t.owner == site.user || t.owner == 'user:${site.user}');

  /// The choices of the plan of [t] with the user's ticks and rights.
  List<StepChoice> choicesOf(AgentTask t) => approvalOf(
    t.plan,
    unticked: assistant.unticked[t.id] ?? const ISetConst({}),
    decides: decidesFor(t),
    // a step the user's grants do not reach is locked; with no `/api/me`
    // read yet, every step that signs is (the gateway checks each again)
    lacks: site.lacks,
  );

  /// The first step of [t] that runs once approved (by [choices]) and
  /// whose arguments are masked because their schema is not known, while
  /// the person has not shown them (`assistant.revealed`); null when none.
  /// Approve waits for it (spec `assistant.md` §3, ADR 0029).
  int? unseenArgs(AgentTask t, List<StepChoice> choices) {
    final shown = assistant.revealed[t.id] ?? const ISetConst<int>({});
    for (final s in t.plan) {
      final runs = choices.where((c) => c.n == s.n).firstOrNull?.runs ?? false;
      if (runs && !s.argsKnown && s.args.isNotEmpty && !shown.contains(s.n)) {
        return s.n;
      }
    }
    return null;
  }

  /// Why this gateway cannot sign for the agent's tasks: the site on
  /// screen is not the gateway's own (ADR 0049, not decided: a downstream
  /// site's agent links are not known here). Null when it can.
  String? get otherSite =>
      site.viewed != null && site.viewed != site.name ? site.viewed : null;
}

/// What the Assistant shows of its tasks, computed from state once
/// (studio-rules §3): the connectors read these and map them.
extension AssistantScreen on Selectors {
  /// The task on screen.
  AgentTask? get shownTask => switch (tasks.selectedTask) {
    final id? => tasks.table[id],
    null => null,
  };

  /// The tasks of the list, newest first: those under way, and those that
  /// ended.
  TaskGroups get taskGroups {
    final now = <AgentTask>[];
    final earlier = <AgentTask>[];
    for (final id in tasks.view.reversed) {
      if (tasks.table[id] case final t?) {
        (t.state.finished ? earlier : now).add(t);
      }
    }
    return TaskGroups(now: now, earlier: earlier);
  }

  /// The lines of [t]'s conversation in this session.
  IList<TaskEvent> sessionOf(AgentTask t) =>
      tasks.events[t.id] ?? const IListConst([]);

  /// The conversation of [t]: this session's lines, or the record's when
  /// there are none; its questions are on the choices card.
  List<TaskEvent> conversationOf(AgentTask t) {
    final session = sessionOf(t);
    return [
      for (final e in session.isEmpty ? t.told : session)
        if (e.kind != TaskEventKind.question) e,
    ];
  }

  /// What the model read in this session, by tool, with how often.
  List<ToolReads> readsOf(AgentTask t) {
    final reads = <String, int>{};
    for (final e in sessionOf(t)) {
      if (e.kind == TaskEventKind.tool) {
        reads[e.text] = (reads[e.text] ?? 0) + 1;
      }
    }
    return [
      for (final MapEntry(:key, :value) in reads.entries) ToolReads(key, value),
    ];
  }

  /// The ticks of the plan of [t]: only for a plan that waits, that no
  /// task replaced (its approve is refused), on the gateway's own site.
  List<StepChoice>? choicesShown(AgentTask t) =>
      t.state == TaskState.awaitingApproval &&
          t.replacedBy == null &&
          otherSite == null
      ? choicesOf(t)
      : null;

  /// Why Approve cannot be pressed for [t] with [choices], in this order:
  /// no record, another site, an approval on its way, nothing ticked, a
  /// masked argument not looked at, no `write` on the task. The approve
  /// action refuses the same way.
  Hold? approveHold(AgentTask t, List<StepChoice> choices) {
    final agent = assistant.agent;
    if (!assistant.docs) {
      return const HoldNoRecord();
    }
    if (otherSite case final s?) {
      return HoldOtherSite(s);
    }
    if (assistant.isApproving) {
      return const HoldBusy();
    }
    if (!choices.any((c) => c.ticked ?? false)) {
      return const HoldNoneTicked();
    }
    if (unseenArgs(t, choices) case final n?) {
      return HoldReveal(n);
    }
    return agent == null
        ? null
        : _lacks(site.lacks(Perm.write, '$agent/tasks/${t.id}'));
  }

  /// What the card of the plan of [t] that waits says beside Approve,
  /// with [choices]: the other half of the decision [approveHold] makes,
  /// in the same order (no record, another site, a refusal, then the
  /// record not read yet, else what Approve signs).
  ApprovalNote approvalNote(AgentTask t, List<StepChoice> choices) {
    if (!assistant.docs) {
      return const ApprovalNoRecord();
    }
    if (otherSite case final s?) {
      return ApprovalOtherSite(s);
    }
    if (assistant.refusals[t.id] case final why?) {
      return ApprovalRefused(why);
    }
    if (!t.recorded) {
      return const ApprovalWaiting();
    }
    return ApprovalSigns(role: site.role ?? '', byAgent: choices.byAgentCount);
  }

  /// Why a task cannot be rejected, cancelled or answered: no `write` on
  /// the agent.
  Hold? get writeHold => switch (assistant.agent) {
    final agent? => _lacks(site.lacks(Perm.write, agent)),
    null => null,
  };

  /// Why nothing can be asked: no agent, no `write` on it, an ask or an
  /// answer on its way.
  Hold? get askHold => assistant.agent == null
      ? const HoldNoAgent()
      : writeHold ??
            (assistant.isAsking || tasks.isAnswering ? const HoldBusy() : null);

  /// Why a suggestion of [t] cannot be picked: no agent, no `write` on it,
  /// an ask on its way, or the user may not follow the task up.
  Hold? followHold(AgentTask t) => assistant.agent == null
      ? const HoldNoAgent()
      : writeHold ??
            (assistant.isAsking ? const HoldBusy() : null) ??
            (mayFollow(t) ? null : const HoldFollow());

  /// Why the steps a run left out cannot be asked for.
  Hold? get followUpHold =>
      writeHold ?? (assistant.isAsking ? const HoldBusy() : null);

  /// Why *Write the plan* cannot be pressed for [t]: no `write`, an answer
  /// on its way, or nothing picked.
  Hold? answerHold(AgentTask t) =>
      writeHold ??
      (tasks.isAnswering
          ? const HoldBusy()
          : (t.questions.every(
                  (q) => q.answered || picksOf(t.id, q.id).isEmpty,
                )
                ? const HoldPickOne()
                : null));

  /// Why *+ from Explorer* cannot add a chip.
  Hold? get chipHold => site.root == null
      ? const HoldNoSite()
      : assistant.chips.length >= maxContextKeys
      ? const HoldChipsFull(maxContextKeys)
      : null;

  /// Why *Make a plan for n units* cannot be pressed for suggestion [s] of
  /// [t]: as any follow-up, or no row ticked.
  Hold? moreHold(AgentTask t, TaskSuggestion s) {
    final picked = rowPicksOf(t.id, s.id);
    return followHold(t) ??
        (s.rows.any((r) => picked.contains(r.key)) ? null : const HoldNoRows());
  }

  /// Whether the secret the agent's `api_key_ref` names is set; null when
  /// that is not known (no `config` to read the names, or no ref).
  bool? get apiKeySet =>
      switch ((assistant.secrets, assistant.config?.apiKeyRef)) {
        (final names?, final ref?) => names.contains(ref),
        _ => null,
      };

  /// Why the agent's modes and prefixes cannot be edited.
  Hold? get editHold => switch (assistant.agent) {
    null => const HoldNoAgent(),
    final agent => _lacks(
      site.lacks(
        Perm.config,
        '${site.root}/sys/links/${agent.split('/').last}/~act/update',
      ),
    ),
  };

  static Hold? _lacks(Lack? lack) => lack == null ? null : HoldLacks(lack);

  /// The agent's mode when it lets a plan's `write` steps run without a
  /// person (`config`, `never`): a picked suggestion's plan may then write
  /// at once (docs/agent.md, AI-4). Null for `write`.
  /// Null for `write`, and when the mode is not known (`modeUnknown` says
  /// so: the screen then keeps the caution).
  ApprovalMode? get unattended => switch (assistant.mode) {
    final m? when m.unattended => m,
    _ => null,
  };

  /// The task a message in the box follows: the task on screen when the
  /// user may follow it and nothing replaced it. A plan that waits is then
  /// replaced by the new one ([replacesPlan] says so before).
  String? askParent(AgentTask? t) =>
      t != null && t.replacedBy == null && mayFollow(t) ? t.id : null;

  /// Sending from the box replaces the plan of [t] that waits.
  bool replacesPlan(AgentTask t) =>
      t.state == TaskState.awaitingApproval && askParent(t) != null;

  /// The picks of question [question] of task [task] on the card.
  ISet<String> picksOf(String task, String question) =>
      assistant.picks['$task/$question'] ?? const ISetConst({});

  /// The rows ticked of suggestion [suggestion] of task [task].
  ISet<String> rowPicksOf(String task, String suggestion) =>
      assistant.rowPicks['$task/$suggestion'] ?? const ISetConst({});

  /// The rows ticked in every *Same for more units?* of [t].
  ISet<RowPick> pickedRowsOf(AgentTask t) => {
    for (final s in t.withRows)
      for (final k in rowPicksOf(t.id, s.id)) RowPick(s.id, k),
  }.lock;

  /// The masked arguments of step [n] of [task] are shown.
  bool revealedOf(String task, int n) =>
      assistant.revealed[task]?.contains(n) ?? false;

  /// The arguments of [s] of [t] as the plan card shows them: each with its
  /// value as it is sent, or null when it is masked (a secret, or a schema
  /// not known and not looked at). A masked value never leaves here.
  List<ShownArg> argsOf(AgentTask t, PlanStep s) {
    final hidden = withheld(s);
    final shown = !s.argsKnown && revealedOf(t.id, s.n);
    return [
      for (final e in s.args.entries)
        ShownArg(
          e.key,
          s.secret.contains(e.key) || (hidden.contains(e.key) && !shown)
              ? null
              : argText(e.value),
        ),
    ];
  }

  /// The findings of [t] Studio shows: those whose key is a plain node key
  /// of the site on screen. The agent link checks this; a record of an
  /// older or a foreign link is not trusted to (a pattern key would be
  /// subscribed).
  List<TaskFinding> findingsShown(AgentTask t) => [
    for (final f in t.findings)
      if (contextKey(site.root, f.key) == f.key) f,
  ];

  /// The nodes the drawer watches for the marks of *What I found*.
  List<String> get drawerFindingKeys => switch (shownTask) {
    final t? when assistant.drawer => [
      for (final f in findingsShown(t)) f.key,
    ],
    _ => const [],
  };

  /// The point the drawer's mini timeline shows: the one selected in
  /// Explorer's points, on the site on screen.
  String? get timelinePoint {
    final p = nodes.point;
    return p != null && site.root != null && p.startsWith('${site.root}/')
        ? p
        : null;
  }

  /// The keys the tab watches while it is shown: those the Result card
  /// shows, and *Today* of What it may do while that panel is shown.
  List<String> get assistantWatch {
    final agent = assistant.agent;
    return [
      ...?shownTask?.touched,
      if (agent != null && assistant.panel == AssistantPanel.rights)
        '$agent/budget_used_today',
    ];
  }

  /// The LLM tokens the agent used today, from its live value.
  num? get budgetUsed =>
      switch (live.values['${assistant.agent}/budget_used_today']?.value) {
        final num n => n,
        _ => null,
      };

  /// The node selected in Explorer, offered as an `@` chip of this site.
  String? get offeredChip {
    final selected = nodes.selectedNode;
    return selected != null &&
            site.root != null &&
            selected.startsWith('${site.root}/') &&
            !assistant.chips.contains(selected)
        ? selected
        : null;
  }

  /// The agent reads [key]: one it does not refuses the whole ask. Before
  /// its settings are read every key is offered.
  bool agentReadsKey(String key) =>
      !assistant.readsKnown ||
      agentReads(site.root ?? '', assistant.agent, assistant.prefixes, key);

  /// The keys *+ from Explorer* offers: the selection and the point
  /// first, then the nodes Explorer read on the site on screen; only plain
  /// node keys of this site the agent reads, none twice, none a chip.
  /// Null when no chip can be added now ([chipHold]: no site, or the
  /// chips are full).
  ChipOffer? get chipChoices {
    final root = site.root;
    if (root == null || chipHold != null) {
      return null;
    }
    final chips = assistant.chips.toSet();
    final selected = offeredChip;
    final point = nodes.point;
    bool fits(String k) =>
        !chips.contains(k) && contextKey(root, k) == k && agentReadsKey(k);
    final first = [
      ?selected,
      if (point != null && point != selected) point,
    ].where(fits).toList();
    return ChipOffer(
      root: root,
      first: first,
      rest: [
        for (final k in nodes.view.take(400))
          if (!first.contains(k) && fits(k)) k,
      ],
    );
  }

  /// The name a chip for [key] shows in the picker: the node's display
  /// name when it has one of its own, else its name; null for a key the
  /// tree has not listed.
  String? chipNameOf(String key) => switch (nodes.table[key]) {
    NodeInfo(:final display?, :final name)
        when display.trim().isNotEmpty && display != name =>
      display,
    final n => n?.name,
  };

  /// The line *No tasks yet* is shown: no task is on screen and the site
  /// has an agent.
  bool get showsNoTasks => shownTask == null && assistant.agent != null;

  /// The rights panel is open.
  bool get rightsShown => assistant.panel == AssistantPanel.rights;

  /// *What I found* is shown for [t]: only in the drawer ([drawer]), and
  /// only with findings, findings the link refused, or the drawer's mini
  /// timeline.
  bool foundShown(AgentTask? t, {required bool drawer}) =>
      drawer &&
      ((t != null &&
              (findingsShown(t).isNotEmpty || t.findingsRefused.isNotEmpty)) ||
          timeline != null);

  /// Whether the masked arguments of [s] of [t] are shown now; null for a
  /// step whose arguments are not masked for an unknown schema (nothing
  /// to reveal).
  bool? revealedShown(AgentTask t, PlanStep s) =>
      s.argsGuessed ? revealedOf(t.id, s.n) : null;

  /// A key typed in the picker, in full or below the site: the plain node
  /// key it names, and whether the agent reads it; null when it names none
  /// or is a chip already.
  TypedChip? typedChip(String text) {
    final root = site.root;
    final k = text.contains('/') ? contextKey(root, text) : null;
    if (root == null || k == null || assistant.chips.contains(k)) {
      return null;
    }
    return TypedChip(k, reads: agentReadsKey(k));
  }
}

/// The Assistant's own decisions over the state.
extension AssistantView on Selectors {
  /// The site has no agent link (known: neither the agent nor the links
  /// are being read).
  bool get noAgent =>
      assistant.agent == null && !assistant.isWaiting && !links.isWaiting;

  /// The card under [t] with the plan's [choices] (null: no ticks are
  /// shown); null for a run that stopped at a step and is not reviewed:
  /// the Stopped card says where and what next.
  TaskStanding? standingOf(AgentTask t, List<StepChoice>? choices) {
    if (t.replacedBy case final next?) {
      // its `~val` may still say it waits
      return StandingReplaced(next);
    }
    final cancel = writeHold;
    switch (t.state) {
      case TaskState.awaitingApproval:
        final shown = choices ?? const <StepChoice>[];
        return StandingApproval(
          note: approvalNote(t, shown),
          runs: shown.tickedCount == 0 ? 0 : shown.runCount,
          rejectHold: cancel,
          approveHold: approveHold(t, shown),
        );
      case TaskState.awaitingAnswer:
        return StandingAnswer(cancelHold: cancel);
      case TaskState.planning || TaskState.running:
        return StandingWorking(cancelHold: cancel);
      case TaskState.done:
        return StandingDone(
          task: t.id,
          leftOut: t.leftOut,
          changedNode: t.changedNode,
          trendPoint: t.touched.lastOrNull,
          savable: t.plan.isNotEmpty,
          followUpHold: followUpHold,
        );
      case TaskState.failed:
        if (t.failedStep == null) {
          return StandingFailed(t.error);
        }
        // while the model reviews the run it can be cancelled
        return t.reviewing ? StandingWorking(cancelHold: cancel) : null;
    }
  }

  /// The line under the plan of [t]: replaced, checked while it waits,
  /// approved, else its state.
  PlanLine planLineOf(AgentTask t) => switch (t.replacedBy) {
    final next? => PlanLineReplaced(next),
    null when t.state == TaskState.awaitingApproval => PlanLineChecked(
      planChecks(t.plan),
    ),
    null => switch (t.approvedBy) {
      final by? => PlanLineApproved(by),
      null => const PlanLineState(),
    },
  };

  /// The questions of [t] are open: the assistant waits for the answer.
  bool answersOpen(AgentTask t) => t.state == TaskState.awaitingAnswer;

  /// *Write the plan* is offered for [t]: its questions are open and one
  /// of them is not answered yet.
  bool confirmsAnswer(AgentTask t) => answersOpen(t) && t.asksStill;

  /// The suggestions of [t] with rows (*Same for more units?*): offered
  /// once the task is done.
  List<TaskSuggestion> moreOf(AgentTask t) =>
      t.state == TaskState.done ? t.withRows : const [];

  /// The ask box for the task [t] on screen, as the tab or the [drawer].
  ComposerState composerOf(AgentTask? t, {required bool drawer}) {
    final answering = t != null && answersOpen(t);
    return ComposerState(
      cue: drawer && !answering
          ? ComposerCue.drawer
          : switch (t?.state) {
              null => ComposerCue.ask,
              TaskState.awaitingAnswer => ComposerCue.answer,
              TaskState.planning => ComposerCue.planning,
              TaskState.awaitingApproval =>
                askParent(t) != null ? ComposerCue.awaiting : ComposerCue.ask,
              TaskState.running => ComposerCue.running,
              TaskState.done => ComposerCue.done,
              TaskState.failed =>
                t?.replacedBy == null ? ComposerCue.failed : ComposerCue.done,
            },
      answering: answering,
      node: t?.failedStep?.key ?? '',
      replaces: !drawer && t != null && replacesPlan(t),
    );
  }

  /// What the model read for the task on screen, shown on *This task*;
  /// nothing on *What it may do* or with no task.
  List<ToolReads> get shownReads => switch (shownTask) {
    final t? when assistant.panel != AssistantPanel.rights => readsOf(t),
    _ => const [],
  };

  /// Why the drawer's timeline shows no audit records; null when it shows
  /// them, or while they are not read yet.
  AuditGap? get timelineAuditGap => !site.readsAudit
      ? AuditGap.needsConfig
      : (timelineAuditRead?.isEmpty ?? false)
      ? AuditGap.none
      : null;

  /// The drawer's second button for [t]: while its plan waits a draft,
  /// after a done task a follow-up; null otherwise, and when another task
  /// replaced it or the model offered none.
  SecondOffer? secondOf(AgentTask t) {
    final s = t.second;
    final waits = t.state == TaskState.awaitingApproval;
    if (s == null ||
        t.replacedBy != null ||
        (!waits && t.state != TaskState.done)) {
      return null;
    }
    return waits
        ? SecondOffer(s, draft: true)
        : SecondOffer(s, draft: false, hold: followHold(t));
  }

  /// The range of the history read for the timeline's point in µs (as
  /// Explorer's): its span up to the last read or the newest row since.
  ExplorerTrendSpan _timelineSpan(IList<HistPoint> rows) {
    final span = nodes.historyRange.span;
    final re = trendRangeEnd(nodes.historyAt, [rows.lastOrNull?.time]);
    final rs = re - span.inMicroseconds;
    final w = nodes.historyWindow;
    final we = w?.end?.microsecondsSinceEpoch ?? re;
    final ws = w == null ? rs : we - w.span.inMicroseconds;
    return (
      rangeStart: rs,
      rangeEnd: re,
      windowStart: ws.clamp(rs, re),
      windowEnd: we.clamp(rs, re),
      minWindow: 12 * stepDuration(stepFor(span, raw: false))!.inMicroseconds,
      following: w?.end == null,
    );
  }

  /// The drawer's mini timeline: the rows Explorer reads for
  /// [timelinePoint] (none until they are its rows); null with no point.
  ExplorerTrend? get timeline {
    final point = timelinePoint;
    if (point == null) {
      return null;
    }
    final read = nodes.historyKey == point;
    final rows = read ? nodes.history : const IListConst<HistPoint>([]);
    final info = nodes.table[point];
    return (
      point: point,
      name: point.split('/').last,
      display: info?.display,
      unit: info?.unit,
      precision: null,
      rows: rows,
      span: _timelineSpan(rows),
      loading: !read || (rows.isEmpty && nodes.historyLoading),
    );
  }

  /// The audit records read for [timelinePoint]; null while those in the
  /// state are another point's (not read yet).
  IList<AuditEntry>? get timelineAuditRead =>
      assistant.timelineKey == timelinePoint ? assistant.timelineAudit : null;

  /// The keys whose live value the Assistant draws: those the Result card
  /// shows and *Today* of What it may do ([assistantWatch]), and for the
  /// [drawer] the nodes of the findings.
  List<String> assistantLiveKeys({required bool drawer}) => [
    ...assistantWatch,
    if (drawer) ...drawerFindingKeys,
  ];
}

/// The params of a link as they will be once the staged update of it is
/// applied (`sys/links/<id>` ▸ `update {params}`, keyed by the link's full
/// key, so another site's link of the same id is not it).
extension StagedParams on Selectors {
  /// The update staged for the agent link [key]: the params it sends and
  /// those it was made from; null when none is staged. Studio writes both
  /// itself (`agentParamsJson`); one that does not read back is logged
  /// and is no base for a new edit.
  StagedAgentParams? stagedAgentParamsOf(String key) {
    for (final c in changes.table.values) {
      if (c.key == key && c.action == 'update') {
        final params = agentParamsOf(c.args['params']).orWarn(key);
        final base = agentParamsOf(c.value).orWarn(key);
        return params == null || base == null
            ? null
            : StagedAgentParams(change: c, params: params, base: base);
      }
    }
    return null;
  }

  /// The agent link's `require_approval` and `allowed_prefixes` as they will
  /// be: from the update staged for it on this site, else as read. The mode
  /// is null when it is not known (the agent's settings did not read).
  AgentParamsShown get agentParams {
    final agent = assistant.agent;
    final staged = agent == null
        ? null
        : stagedAgentParamsOf(
            '${site.root}/sys/links/${agent.split('/').last}',
          );
    return AgentParamsShown(
      mode: staged?.params.requireApproval ?? assistant.mode,
      prefixes: (staged?.params.allowedPrefixes ?? assistant.prefixes).toList(),
      staged: staged != null,
    );
  }
}

/// Values that belong to the app rather than to one slice. They sit on the
/// facade rather than on any one substate's selectors, which is what
/// `on Selectors` says — and it is the place for a value that reads two
/// slices at once, since a `SelectX` does not reach its siblings.
///
/// It used to also hold `canEnterApp` — a token and no login in flight — which
/// nothing read: the auth guard decides on `session.isAvailable` alone, because
/// the login action writes the token in the same reduce that clears the form,
/// so "logged in and still waiting on login" is not a state anything can
/// observe. `frx graph` listed it under "nothing reaches"; now it is gone.
/// What Explorer shows, computed from the state (`wyrm/explorer.dart`).
extension ExplorerSelect on Selectors {
  ExplorerView get explorer => ExplorerView(state);
}

extension SelectComposites on Selectors {
  /// Whether any foreground operation is in flight — what the modal barrier
  /// covers.
  ///
  /// **Folded off `Wait`, not named slice by slice.** The barrier read
  /// `login.isWaiting || registration.isWaiting`, and the two features written
  /// after that line showed no loading state at all: both mix in
  /// `WaitingAction`, both have an `isWaiting` getter, and neither was in the
  /// disjunction. A list of the slices that count is a list somebody has to
  /// remember, and it was already wrong.
  ///
  /// **Keyed on `BlockingAction`, which is a claim, not a side effect.** Two
  /// narrower predicates were tried and both were too wide. `isWaitingAny` is
  /// true for any flag in `Wait`, including ones that are not actions.
  /// `isWaitingForType<WaitingAction>()` looks narrower and is not: every async
  /// action that wants an indicator mixes in `WaitingAction`, because that is
  /// what puts it in `Wait` — so the first background refresh anyone adds would
  /// blank the app.
  ///
  /// `BlockingAction` is written on purpose and means only this. The set stays
  /// a fold rather than a list: `WaitAction.add(this)` files the action as the
  /// flag and `isWaitingForType<T>` tests `flag is T`, so the mixin answers for
  /// every action carrying it and nothing here names any of them.
  bool get isBusy => state.wait.isWaitingForType<BlockingAction>();

  /// The workspaces reading again what they show.
  ISet<Workspace> get refreshingWorkspaces => refreshingWorkspacesOf(state);

  /// [ws] is reading again data it already shows: stale while revalidate
  /// (docs/studio.md §6.7). The workspace keeps its content and the shell
  /// lays the sweep bar over it.
  ///
  /// **Two halves, both needed.** A read of the workspace is in flight — one
  /// of the `Retrieve…` actions it dispatches when it is shown, read off
  /// `Wait` like every other `isWaiting` — *and* its slice already holds
  /// something to keep on screen. In flight with nothing held is a first
  /// load, which stays the workspace's own empty or loading state.
  ///
  /// Only reads count. A command in flight (Start, Deploy, Install, Apply)
  /// has its own busy control and is not a refresh.
  bool refreshing(Workspace ws) {
    final w = state.wait;
    return switch (ws) {
      .explorer =>
        state.nodes.table.isNotEmpty &&
            (w.isWaitingForType<RetrieveNodeDetailAction>() ||
                w.isWaitingForType<RetrieveHistoryAction>() ||
                w.isWaitingForType<RetrieveLinksAction>()),
      .links =>
        (state.links.table.isNotEmpty || state.quarantine.table.isNotEmpty) &&
            (w.isWaitingForType<RetrieveLinksAction>() ||
                w.isWaitingForType<RetrieveQuarantineAction>() ||
                w.isWaitingForType<RetrievePackagesAction>()),
      .flows =>
        state.flows.table.isNotEmpty &&
            w.isWaitingForType<RetrieveFlowsAction>(),
      .history =>
        state.historian.groups.isNotEmpty &&
            (w.isWaitingForType<RetrieveHistorianAction>() ||
                w.isWaitingForType<RetrieveSeriesAction>()),
      .access =>
        (state.access.users.isNotEmpty || state.access.grants.isNotEmpty) &&
            w.isWaitingForType<RetrieveAccessAction>(),
      .sites =>
        (state.peers.table.isNotEmpty || state.site.choices.isNotEmpty) &&
            (w.isWaitingForType<RetrievePeersAction>() ||
                w.isWaitingForType<RetrieveSitesAction>() ||
                w.isWaitingForType<RetrieveQuarantineAction>() ||
                w.isWaitingForType<RetrieveLinksAction>()),
      .assistant =>
        (state.tasks.table.isNotEmpty || state.assistant.agent != null) &&
            (w.isWaitingForType<RetrieveAgentAction>() ||
                w.isWaitingForType<RetrieveTasksAction>()),
      .system =>
        (state.system.log.isNotEmpty &&
                w.isWaitingForType<RetrieveSystemLogAction>()) ||
            (state.system.profiles.isNotEmpty &&
                w.isWaitingForType<RetrieveProfilesAction>()),
    };
  }
}

/// A link name: a key segment of letters, digits, `.`, `_`, `-`.
final _linkName = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

/// What Add a link shows, computed from state once (studio-rules §3): the
/// connector maps these, it decides none of them.
extension LinkInstallScreen on Selectors {
  /// The steps of the path: the official list Choose → Where → Install; a
  /// custom package or a backup Bring → Check → Where → Install.
  List<InstallStep> get installSteps => switch (linkInstall.path) {
    InstallPath.official => const [
      InstallStep.choose,
      InstallStep.run,
      InstallStep.result,
    ],
    InstallPath.custom || InstallPath.backup => InstallStep.values,
  };

  /// The step on screen, one of [installSteps].
  InstallStep get installStep => installSteps.contains(linkInstall.step)
      ? linkInstall.step
      : installSteps.first;

  /// The wizard is at its last step: the result of the install.
  bool get installEnded => installStep == InstallStep.result;

  /// The item of the official list picked; null before one is.
  CatalogItem? get installItem =>
      linkInstall.catalog.where((c) => c.id == linkInstall.item).firstOrNull;

  /// The broker the new link goes to.
  String get installBroker => linkInstall.broker ?? site.viewed ?? '';

  /// What was brought, as the user knows it: the file's name, the URL,
  /// the driver or the package; null before anything is.
  String? get installSourceName => switch (linkInstall.source) {
    null => null,
    InstallSourceZip(:final fileName) ||
    InstallSourceBackup(:final fileName) ||
    InstallSourceWasm(:final fileName) => fileName,
    InstallSourceUrl(:final url) || InstallSourceGit(:final url) => url,
    InstallSourceBuiltIn(:final driver) => driver,
    InstallSourceRepository(:final package) => package,
  };

  /// The name of the file brought (a zip, a component, a backup); null
  /// for a URL or nothing.
  String? get installFileName => switch (linkInstall.source) {
    InstallSourceZip(:final fileName) ||
    InstallSourceBackup(:final fileName) ||
    InstallSourceWasm(:final fileName) => fileName,
    _ => null,
  };

  /// The URL brought: the package's, or the Git repository's.
  String? get installUrl => switch (linkInstall.source) {
    InstallSourceUrl(:final url) || InstallSourceGit(:final url) => url,
    _ => null,
  };

  /// The Git ref brought.
  String? get installRef => switch (linkInstall.source) {
    InstallSourceGit(:final ref) => ref,
    _ => null,
  };

  /// The branch of the link just installed: `wy/<broker>/downstream/<name>`.
  String get installedLinkKey =>
      'wy/$installBroker/downstream/${linkInstall.name ?? ''}';

  /// The official list of the category on screen. The words searched for
  /// are matched by `catalogHit` (`wyrm/search.dart`) against what the
  /// broker says of an item and what its card reads on screen; the app's
  /// mapper hands in what the card reads (a known driver's title and line
  /// are `ui`'s words, in the language on screen).
  List<CatalogItem> get installShownCatalog {
    final category = linkInstall.category;
    return [
      for (final c in linkInstall.catalog)
        if (category == null || c.category == category) c,
    ];
  }

  /// The categories of the official list, each once.
  List<CatalogCategory> get installCategories =>
      categoriesOf(linkInstall.catalog);

  /// A check of the package or the backup failed.
  bool get installCheckFailed => linkInstall.checks.any(
    (c) => c.result == PackageCheckResult.failed,
  );

  /// A link of the backup's id is on the broker: the install replaces it
  /// (in place, after a restore point).
  bool get installReplaces =>
      linkInstall.path == InstallPath.backup &&
      installBroker == site.viewed &&
      links.table.containsKey(linkInstall.name);

  /// What is wrong with the name; null when nothing is, or no name is
  /// given yet. What the broker said of a name it refused stays until the
  /// name changes (docs/design/specs/errors.md §3, *Back to the form*).
  InstallNameProblem? get installNameProblem {
    final name = linkInstall.name ?? '';
    if (name.isEmpty) {
      return null;
    }
    if (!_linkName.hasMatch(name)) {
      return InstallNameProblem.rule;
    }
    // A backup may replace the link of its id: the name is then no
    // problem.
    if (linkInstall.path != InstallPath.backup &&
        installBroker == site.viewed &&
        links.table.containsKey(name)) {
      return InstallNameProblem.taken;
    }
    return linkInstall.refusedField == InstallField.name
        ? InstallNameProblem.refused
        : null;
  }

  /// The rights must be accepted before Install: a package that asks for
  /// some. A backup's grants are in its sealed part: the broker lists them
  /// when the install needs `accept`, so accepting is offered, not asked.
  bool get installNeedsRights =>
      linkInstall.path != InstallPath.backup &&
      (linkInstall.rights != null || !(installItem?.builtIn ?? true));

  /// *Accept requested rights* is offered.
  bool get installOffersAccept =>
      linkInstall.path == InstallPath.backup || installNeedsRights;

  /// Why the user may not install on the broker: no config on its
  /// `sys/links`; null when they may.
  Lack? get installConfigReason => installTargetReason(installBroker);

  /// Why the user may not install on the broker of [site]: no config on
  /// its `sys/links`; null when they may.
  Lack? installTargetReason(String site) =>
      this.site.lacks(Perm.config, 'wy/$site/sys/links');

  /// The brokers a link can go to, each with whether it is the site on
  /// screen and why the user may not install there.
  List<InstallBroker> get installBrokers => [
    for (final t in linkInstall.targets)
      InstallBroker(
        t,
        here: t.site == site.viewed,
        refused: installTargetReason(t.site),
      ),
  ];

  /// How the new link can run there, the one to pick first.
  List<LinkMode> get installModes => switch (linkInstall.path) {
    InstallPath.official =>
      installItem?.modes.unlock ?? const [LinkMode.embedded],
    InstallPath.backup => [linkInstall.mode ?? LinkMode.process],
    InstallPath.custom => [
      if (linkInstall.mode == LinkMode.wasm)
        LinkMode.wasm
      else
        LinkMode.process,
    ],
  };

  /// How the new link runs.
  LinkMode get installMode => linkInstall.mode ?? installModes.first;

  /// Why the step on screen offers no *Continue* (or *Install*); null when
  /// it does, and on the last step.
  InstallBlock? get installBlock {
    final li = linkInstall;
    return switch (installStep) {
      InstallStep.choose
          when li.path == InstallPath.official && installItem == null =>
        InstallBlock.pickOne,
      InstallStep.choose
          when li.path != InstallPath.official && li.source == null =>
        InstallBlock.bringOne,
      InstallStep.check when installCheckFailed => InstallBlock.checkFailed,
      InstallStep.run when (li.name ?? '').isEmpty => InstallBlock.nameIt,
      InstallStep.run when installNameProblem != null =>
        InstallBlock.nameProblem,
      InstallStep.run when installNeedsRights && !li.acceptRights =>
        InstallBlock.acceptFirst,
      InstallStep.run when installConfigReason != null =>
        InstallBlock.needsConfig,
      _ => null,
    };
  }
}

/// The package a link runs (`pkg:<name>`), or null for a built-in driver.
String? packageOfLink(LinkInfo l) =>
    l.driver.startsWith('pkg:') ? l.driver.substring(4) : null;

final _linkStates = LastResult<Map<String, LinkState>>();
final _livePackages = LastResult<Map<String, PackageInfo>>();
final _restorePoints = LastResult<Map<String, List<RestorePoint>>>();

/// What Links shows, computed from state once (studio-rules §3): the live
/// values of its links and packages are decoded once per change of their
/// own keys (a value of another type is logged, and the table's stays).
extension LinksTables on Selectors {
  String get _linksRoot => site.root ?? '';

  /// The keys Links watches while shown: each link's state and restore
  /// points, the admission options, and what moves while a package is
  /// updated (ADR 0048 §1).
  List<String> get linksKeys => [
    '$_linksRoot/sys/links/*/state',
    '$_linksRoot/sys/enable_quarantine',
    '$_linksRoot/sys/allow_all_links',
    '$_linksRoot/sys/packages/*/*',
    '$_linksRoot/sys/links/*/restore_points',
  ];

  Object? _live(String key) => live.values['$_linksRoot/sys/$key']?.value;

  /// The state of each link: its live `sys/links/<id>/state` when watched.
  Map<String, LinkState> get _states => _linkStates.of(
    [
      site.root,
      links.view,
      for (final id in links.view)
        live.values['$_linksRoot/sys/links/$id/state'],
    ],
    () => {
      for (final id in links.view)
        if (_live('links/$id/state') case final v?)
          id: ?linkStateSampleOf(v).orWarn('sys/links/$id/state'),
    },
  );

  /// The state of [link]: its live `sys/links/<id>/state` when watched,
  /// else what was read with the list.
  LinkState stateOfLink(LinkInfo link) => _states[link.id] ?? link.state;

  /// The link [id] was connected when the list was read.
  bool linkListedConnected(String id) =>
      links.table[id]?.state == LinkState.connected;

  /// The installed packages with their live values.
  Map<String, PackageInfo> get _packages => _livePackages.of(
    [
      site.root,
      packages.table,
      for (final name in packages.table.keys)
        for (final leaf in packageLeaves)
          live.values['$_linksRoot/sys/packages/$name/$leaf'],
    ],
    () => {
      for (final MapEntry(:key, :value) in packages.table.entries)
        key: packageLiveOf(
          value,
          (leaf) => _live('packages/$key/$leaf'),
          where: 'sys/packages/$key',
        ),
    },
  );

  /// The package [name] with its live values; null when not installed.
  PackageInfo? livePackage(String? name) =>
      name == null ? null : _packages[name];

  /// The package [l] runs, with its live values; null for a built-in
  /// driver.
  PackageInfo? packageRunBy(LinkInfo l) => livePackage(packageOfLink(l));

  /// The repository lists [p]: `latest` is empty for a custom package.
  bool isOfficialPackage(PackageInfo p) => p.latest.isNotEmpty;

  /// The links that run the package [name], by id, in list order.
  List<String> linksOfPackage(String name) => [
    for (final id in links.view)
      if (links.table[id]?.driver == 'pkg:$name') id,
  ];

  /// The restore points of [link] (`sys/links/<id>/restore_points`).
  List<RestorePoint> restorePointsOfLink(String link) =>
      _restorePoints.of(
        [
          site.root,
          links.view,
          for (final id in links.view)
            live.values['$_linksRoot/sys/links/$id/restore_points'],
        ],
        () => {
          for (final id in links.view)
            id:
                restorePointsOf(
                  _live('links/$id/restore_points'),
                  where: 'sys/links/$id/restore_points',
                ).orWarn('sys/links/$id/restore_points') ??
                const [],
        },
      )[link] ??
      const [];

  /// The links of the site in list order: those that run here, and those
  /// on other devices.
  List<LinkInfo> get _allLinks => [
    for (final id in links.view) ?links.table[id],
  ];
  List<LinkInfo> get localLinks => [
    for (final l in _allLinks)
      if (l.mode != LinkMode.external) l,
  ];
  List<LinkInfo> get remoteLinks => [
    for (final l in _allLinks)
      if (l.mode == LinkMode.external) l,
  ];

  /// The entries of `sys/quarantine`, in list order.
  List<QuarantineEntry> get quarantined => [
    for (final n in quarantine.view) ?quarantine.table[n],
  ];

  /// The rows of Updates: the links of a package with a newer version, and
  /// the links of a custom package (updated from a file).
  List<LinkInfo> get linksToUpdate => [
    for (final l in localLinks)
      if (packageRunBy(l) case final p?
          when p.updateAvailable || !isOfficialPackage(p))
        l,
  ];

  /// The official packages with a newer version, in the order of the
  /// links.
  List<String> get updatablePackages => {
    for (final l in _allLinks)
      if (packageRunBy(l) case final p? when p.updateAvailable) p.name,
  }.toList();

  /// How many links of Updates have a newer version: the live values of
  /// the packages once read, the attribute of `sys/links` until then.
  int get updateCount => packages.view.isEmpty
      ? links.updatesAvailable
      : linksToUpdate.where((l) => packageRunBy(l)!.updateAvailable).length;

  /// The Updates tab is shown: hidden at 0 (spec §1), and while it is the
  /// tab on screen.
  bool get showsUpdates => updateCount > 0 || links.tab == LinksTab.updates;

  /// Why the user may not install or update links; null when they may.
  Lack? get linksConfigReason =>
      site.lacks(Perm.config, '$_linksRoot/sys/links');

  /// Why the user may not change the link [id]; null when they may.
  Lack? linkConfigReason(String id) =>
      site.lacks(Perm.config, '$_linksRoot/sys/links/$id');

  /// Why the user may not change the admission options on `sys`.
  Lack? get admissionReason => site.lacks(Perm.config, '$_linksRoot/sys');

  /// Why the user may not decide for the quarantine entry [node]; null
  /// when they may.
  Lack? quarantineReason(String node) =>
      site.lacks(Perm.config, '$_linksRoot/sys/quarantine/$node');

  /// `sys/enable_quarantine` and `sys/allow_all_links` as the broker says
  /// them (false when it says nothing).
  bool get holdsUnknown => _live('enable_quarantine') == true;
  bool get allowsAllLinks => _live('allow_all_links') == true;

  /// The update sheet open, or null.
  LinkUpdate? get linkUpdate {
    final p = livePackage(updates.package);
    if (p == null) {
      return null;
    }
    final ids = linksOfPackage(p.name);
    final row = linkInstall.catalog
        .where((c) => c.id == 'package:${p.name}')
        .firstOrNull;
    return LinkUpdate(
      package: p,
      links: ids,
      follow: updates.view != UpdateView.review,
      official: isOfficialPackage(p),
      title: row?.name,
      summary: row?.description,
      takePoint: updates.takePoint,
      autoRollback: updates.autoRollback,
      acceptNew: updates.acceptNew,
      asks: updates.asks,
      said: updates.message,
      busy: updates.isWaiting,
      rollingBack: updates.isRollingBack,
      seenAt: updates.seenAt,
      points: [
        for (final id in ids)
          for (final point in restorePointsOfLink(id)) LinkPoint(id, point),
      ]..sort((a, b) => b.point.at.compareTo(a.point.at)),
      queue: updates.queue.unlock,
      reason: linksConfigReason,
    );
  }
}

/// What System says about the broker on screen, from the values it serves
/// under `sys` (specs/system.md). They read `live`, `links`, `quarantine`
/// and `system` at once, so they sit on the facade.
extension SelectBrokerHealth on Selectors {
  String get _sysKey => '${site.root}/sys';

  /// What a decode of [keys] below `sys` reads: the site, and the live
  /// value of each key (the same object while it does not change).
  List<Object?> _sysInputs(Iterable<String> keys) => [
    site.viewed,
    for (final k in keys) live.values['$_sysKey/$k'],
  ];

  /// The values of `sys`, decoded once per change of their own live
  /// values, not on a tick of another point (a value of another type is
  /// left out and logged).
  SysStatus get sysStatus => _sysStatus.of(
    _sysInputs(sysStatusKeys),
    () => sysStatusOf(
      (k) => live.values['$_sysKey/$k']?.value,
      'sys of ${site.viewed}',
    ),
  );

  /// The `description` of the node of [v] (a tile's tooltip); empty
  /// before it was read.
  String sysAbout(SysValue v) => system.about['$_sysKey/${v.key}'] ?? '';

  /// The unit the node of [v] names, if any.
  String? sysUnit(SysValue v) => system.units['$_sysKey/${v.key}'];

  /// The Log tab reads the log again every 5 s: `every 5 s` is on, the
  /// tab is shown and the user may read it.
  bool get systemLogPolls =>
      system.auto && system.tab == SystemTab.log && sysConfigReason == null;

  /// Why the user may not change `sys` (`config` on it); null when they
  /// may.
  Lack? get sysConfigReason => site.lacks(Perm.config, _sysKey);

  /// The links `sys ▸ clear_conns` would remove, by the broker's own rule
  /// (wyrm-admin `clear_conns`): mode external, admitted at runtime, not
  /// connected now.
  List<LinkInfo> get clearableLinks => [
    for (final id in links.view)
      if (links.table[id] case final l?)
        if (l.mode == LinkMode.external &&
            l.origin == LinkOrigin.runtime &&
            stateOfLink(l) != LinkState.connected)
          l,
  ];

  /// The links whose state is failed, in list order.
  List<LinkInfo> get failedLinks => [
    for (final id in links.view)
      if (links.table[id] case final l? when stateOfLink(l) == LinkState.failed)
        l,
  ];

  /// The entries of `sys/quarantine` that wait (not held back by
  /// Deauthorize), in list order.
  List<QuarantineEntry> get _waiting => [
    for (final id in quarantine.view)
      if (quarantine.table[id] case final q? when !q.deauthorized) q,
  ];

  /// The link that has waited in quarantine longest (no time: first).
  QuarantineEntry? get oldestWaitingLink =>
      ([
            for (final q in _waiting)
              if (q.kind != QuarantineKind.broker) q,
          ]..sort(
            (a, b) => (a.firstSeen ?? DateTime(0)).compareTo(
              b.firstSeen ?? DateTime(0),
            ),
          ))
          .firstOrNull;

  /// The first connected peer of [kind], while `sys` says one of that
  /// kind is connected.
  String? connectedPeer(PeerKind kind) {
    final count = switch (kind) {
      PeerKind.upstream => sysStatus[SysValue.upstreamConnected],
      PeerKind.downstream => sysStatus[SysValue.downstreamConnected],
      // `sys` counts only the brokers above and below
      PeerKind.relayed || PeerKind.platform || PeerKind.device => null,
    };
    if ((count ?? 0) <= 0) {
      return null;
    }
    return peers.table.values
        .where((p) => p.kind == kind && p.connected)
        .map((p) => p.site)
        .firstOrNull;
  }

  /// The warm standby, from `standby_connected`, `standby_lag` and
  /// `standby_forks`.
  StandbyState get standby {
    final status = sysStatus;
    final connected = status[SysValue.standbyConnected];
    if (connected == null) {
      return StandbyState.unknown;
    }
    if (connected <= 0) {
      return StandbyState.none;
    }
    return (status[SysValue.standbyLag] ?? 0) > 0 ||
            (status[SysValue.standbyForks] ?? 0) > 0
        ? StandbyState.behind
        : StandbyState.following;
  }

  /// The cards of the attention panel, in its order: the standby behind,
  /// each failed link, each quarantine entry, each downstream broker that
  /// waits for Authorize, the ACL counter grown since the screen was last
  /// shown, and last that no standby follows.
  List<AttentionItem> get attention {
    final status = sysStatus;
    final lag = status[SysValue.standbyLag] ?? 0;
    final forks = status[SysValue.standbyForks] ?? 0;
    final waiting = _waiting;
    final acl = status[SysValue.aclDenied];
    final seen = system.aclSeen;
    return [
      if (lag > 0 || forks > 0)
        AttentionItem(
          kind: AttentionKind.standbyBehind,
          count: lag.round(),
          more: forks.round(),
        ),
      for (final l in failedLinks)
        AttentionItem(kind: AttentionKind.linkFailed, subject: l.id),
      for (final q in waiting)
        if (q.kind != QuarantineKind.broker)
          AttentionItem(
            kind: AttentionKind.quarantine,
            subject: q.node,
            name: q.cn,
            since: q.firstSeen,
          ),
      for (final q in waiting)
        if (q.kind == QuarantineKind.broker)
          AttentionItem(
            kind: AttentionKind.brokerWaiting,
            subject: q.node,
            name: q.cn,
            count: q.via.length,
          ),
      if (acl != null && seen != null && acl > seen)
        AttentionItem(
          kind: AttentionKind.aclGrown,
          count: (acl - seen).round(),
          more: seen,
        ),
      if (standby == StandbyState.none)
        const AttentionItem(kind: AttentionKind.noStandby),
    ];
  }

  /// The level the broker logs at.
  LogLevel? get brokerLogLevel => sysStatus.logLevel;

  /// The change of `sys/log_level` staged in Review and apply, if any.
  StagedChange? get stagedLogLevel => changes.table.values
      .where((c) => c.key == '$_sysKey/log_level' && c.field == 'value')
      .firstOrNull;

  /// The level the Log tab shows as the broker's: the staged one, else
  /// the broker's own, else `info`.
  LogLevel get shownLogLevel =>
      switch (stagedLogLevel) {
        StagedChange(to: ChangeSideText(:final text)) => LogLevel.fromWire(
          text,
        ),
        _ => null,
      } ??
      brokerLogLevel ??
      LogLevel.info;

  /// The lines the log box shows: all that were read, or the ones near the
  /// toolbar's time. Copy and Save as .log write these.
  List<LogLine> get shownLog => linesAround(system.log, system.around);

  /// The links whose own log the Log toolbar can read: embedded and WASM
  /// links (a process link's log is its own).
  List<LinkInfo> get logSourceLinks => [
    for (final id in links.view)
      if (links.table[id] case final l?
          when l.mode == LinkMode.embedded || l.mode == LinkMode.wasm)
        l,
  ];

  /// The kept backup [id] with its live values, or null.
  BackupJob? backupJob(String id) => switch (backups.table[id]) {
    final j? => backupLiveOf(
      j,
      (leaf) => live.values['$_sysKey/backups/$id/$leaf']?.value,
      '$_sysKey/backups/$id',
    ),
    null => null,
  };

  /// The kept backups with their live values, newest first (the ids are in
  /// the order the broker made them).
  List<BackupJob> get backupRows => _backupRows.of(
    [
      backups.table,
      backups.view,
      ..._sysInputs([
        for (final id in backups.view)
          for (final leaf in backupLeaves) 'backups/$id/$leaf',
      ]),
    ],
    () => [for (final id in backups.view.reversed) ?backupJob(id)],
  );

  /// The broker's update as System offers it: null while the broker part
  /// does not exist ([Features.brokerUpdate]) and for a broker that says
  /// nothing of it.
  BrokerSelfUpdate? get offeredSelfUpdate => switch (selfUpdate) {
    final u when Features.brokerUpdate && u.known => u,
    _ => null,
  };

  /// What the broker says of its own update (ADR 0048 §2.4).
  BrokerSelfUpdate get selfUpdate => _selfUpdate.of(
    _sysInputs(selfUpdateKeys),
    () => brokerSelfUpdateOf(
      (k) => live.values['$_sysKey/$k']?.value,
      'update of ${site.viewed}',
    ),
  );

  /// The traffic trend's range (the ring's first and last sample, µs), the
  /// window on it (the stored one, else all of it, clamped to the range),
  /// whether the window follows now, and the narrowest window (ten
  /// samples at the ring's pace); null before two samples.
  TrafficTrendView? get trafficTrend {
    final samples = system.samples;
    if (samples.length < 2) {
      return null;
    }
    final rs = samples.first.time.microsecondsSinceEpoch;
    final re = samples.last.time.microsecondsSinceEpoch;
    final w = system.trafficWindow;
    final we = w?.end?.microsecondsSinceEpoch ?? re;
    final ws = w == null ? rs : we - w.span.inMicroseconds;
    return (
      rangeStart: rs,
      rangeEnd: re,
      windowStart: ws.clamp(rs, re),
      windowEnd: we.clamp(rs, re),
      minWindow: 10 * ((re - rs) ~/ (samples.length - 1)),
      following: w?.end == null,
    );
  }
}

final _sysStatus = LastResult<SysStatus>();
final _backupRows = LastResult<List<BackupJob>>();
final _selfUpdate = LastResult<BrokerSelfUpdate>();

/// The range and window of System's traffic trend (µs), as
/// [SelectBrokerHealth.trafficTrend] gives them.
typedef TrafficTrendView = ({
  int rangeStart,
  int rangeEnd,
  int windowStart,
  int windowEnd,
  int minWindow,
  bool following,
});

extension type SelectConnectivity(AppState _state) {
  bool get isConnected => _state.connectivity.isAvailable;
}

extension type SelectLogin(AppState _state) {
  /// Returns password value
  String? get password => _state.login.password;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<LogInAction>();

  /// Returns gateway
  String? get gateway => _state.login.gateway;

  /// Returns user
  String? get user => _state.login.user;

  /// Returns step
  int get step => _state.login.step;

  /// Returns recent
  IList<String> get recent => _state.login.recent;

  /// Returns probes
  IMap<String, int> get probes => _state.login.probes;

  /// Returns remember
  bool get remember => _state.login.remember;

  /// Returns failure
  LoginFailure? get failure => _state.login.failure;

  /// Returns reason
  AnswerFault? get reason => _state.login.reason;

  /// Returns isProbing
  bool get isProbing => _state.wait.isWaitingForType<ProbeGatewayAction>();

  /// Returns preload
  int get preload => _state.login.preload;

  /// Returns preloadLate
  IList<int> get preloadLate => _state.login.preloadLate;

  /// The labels of the recent gateways and of the field's gateway by origin
  /// (`gatewayKey`), host:port where a host alone is ambiguous
  /// (`labelGateways`, docs/design/specs/login.md §3.2).
  IMap<String, String> get gatewayLabels => labelGateways(
    _state.login.recent,
    _state.login.gateway ?? defaultGateway,
  );

  /// The gateway field as a main and a standby (ADR 0036).
  GatewayField get field => GatewayField.of(_state.login.gateway);

  /// The field's main gateway as its chip and the status line name it
  /// (`gatewayLabel`); what is typed while it is not a URL.
  String get fieldLabel {
    final f = field;
    final uri = f.mainUri;
    return uri == null ? f.main : gatewayLabels[uri.origin] ?? shortHost(uri);
  }

  /// The last probe of the field's main gateway, in milliseconds; null
  /// before one, -1 without an answer.
  int? get fieldProbe => switch (field.mainUri) {
    final u? => _state.login.probes[u.origin],
    null => null,
  };

  /// The field's gateway did not answer: the log-in or its probe.
  bool get down =>
      _state.login.failure == LoginFailure.unreachable || fieldProbe == -1;

  /// The user of the form, as typed.
  String get formUser => (_state.login.user ?? '').trim();

  /// The field's gateway as its dot shows it.
  FieldState get fieldState => SelectDiscovery(_state).pendingRow != null
      ? FieldState.trustPending
      : down
      ? FieldState.down
      : fieldProbe == null
      ? FieldState.unknown
      : FieldState.answered;

  /// The status line under the field; null for none.
  FieldNote? get fieldNote {
    final picked = SelectDiscovery(_state).pickedInField;
    final ms = fieldProbe;
    return switch ((picked, down, ms)) {
      (final p?, false, _) => FieldPicked(
        p.site,
        withStandby: p.standby != null,
      ),
      (_, true, _) => FieldNoAnswer(fieldLabel),
      (_, false, null) => field.main.isEmpty ? const FieldEmpty() : null,
      (_, false, final ms?) => FieldAnswered(fieldLabel, ms),
    };
  }

  /// The key here can be tried: the gateway answers and a key is there.
  bool get keyReady => !down && _state.device.keyId != null;

  /// The site of the unlock form's TLS line: the key's site for an
  /// `https` gateway; null for a plain one.
  String? get keyTlsSite => field.https ? keySite : null;

  /// The site a device key here is for: the key's own, else the field's
  /// gateway by its short name.
  String get keySite {
    final uri = field.mainUri;
    return _state.device.keySite ?? (uri == null ? field.main : shortHost(uri));
  }

  /// The recent gateways as their chips show them.
  List<RecentGateway> get recentGateways => recentGatewaysOf(
    _state.login.recent,
    gatewayLabels,
    _state.login.probes,
    _state.login.gateway ?? defaultGateway,
  );

  /// What the footer's TLS line says of the field's gateway; null for a
  /// plain one.
  TlsLine? get tlsLine {
    final uri = field.mainUri;
    final pending = SelectDiscovery(_state).pendingRow;
    final pin = uri == null ? null : _state.discovery.pins[uri.origin];
    final short = uri == null ? field.main : shortHost(uri);
    final site = _state.site;
    final ours =
        site.gateway != null &&
        site.name != null &&
        site.gateway!.origin == uri?.origin;
    final https = uri?.isScheme('https') ?? false;
    return switch ((pending, pin, https)) {
      (final p?, _, _) => TlsNotTrusted(p.site),
      (null, final p?, _) => TlsPinned(p.site.isEmpty ? short : p.site),
      (null, null, true) => TlsCertificate(ours ? site.name! : short),
      (null, null, false) => null,
    };
  }
}

extension type SelectSession(AppState _state) {
  /// Returns session token
  String? get token => _state.session.token;

  /// Returns true if session is available
  bool get isAvailable => token != null;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<LogOutAction>();
}

extension type SelectTheme(AppState _state) {
  /// Returns the selected theme mode
  ThemeMode get mode => _state.theme.mode;
}

extension type SelectLanguage(AppState _state) {
  /// Returns the selected locale code (e.g. `en`)
  String get locale => _state.language.locale;
}

extension type SelectSite(AppState _state) {
  /// Returns gateway
  GatewayAddress? get gateway => _state.site.gateway;

  /// Returns user
  String? get user => _state.site.user;

  /// Returns name
  String? get name => _state.site.name;

  /// Returns role
  String? get role => _state.site.role;

  /// Returns connected
  bool get connected => _state.site.connected;

  /// The site on screen: the one picked in the switcher, else the one
  /// logged into.
  String? get viewed => _state.site.current ?? _state.site.name;

  /// The site on screen is the one logged into.
  bool get viewsHome => viewed == _state.site.name;

  /// `wy/<viewed site>`, the root every screen's keys start from.
  String? get root => viewed == null ? null : 'wy/$viewed';

  /// `wy/<site logged into>`: where `/api/me` and the gateway live.
  String? get home =>
      _state.site.name == null ? null : 'wy/${_state.site.name}';

  /// Returns current
  String? get current => _state.site.current;

  /// Returns grants
  IList<Grant> get grants => _state.site.grants;

  /// Returns choices
  IList<SiteChoice> get choices => _state.site.choices;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveSitesAction>();

  /// The user's level on [key], as the gateway signs it (`Grants::perm`,
  /// roles.rs) and the link reads it (spec 04, `wyrm_core::ptok::level_on`):
  /// the FIRST grant whose pattern matches decides, so a narrower grant
  /// before a wider one (a `read`, or a `none`) wins over it; no match is
  /// `none`. Capped by `max`. Grants below an upstream are rewritten for the
  /// downstream site by the gateway, so the patterns are full keys.
  Perm levelOn(String key) {
    for (final g in _state.site.grants) {
      if (keyMatches(g.key, key)) {
        return _capped(g.level);
      }
    }
    return Perm.none;
  }

  /// [level] capped by the session's `max` (`/api/me`), as the gateway caps
  /// every grant (`Grants::perm`): no level above it is shown or signed.
  /// No `max` (`/api/me` not read): the cap is closed, no level at all.
  Perm _capped(Perm level) => switch (max) {
    final m? when m < level => m,
    _? => level,
    null => Perm.none,
  };

  /// The user has at least [level] on [key].
  bool can(Perm level, String key) => levelOn(key) >= level;

  /// The user's level under `downstream` of the site on screen (the
  /// shell's rights line).
  Perm get downstreamLevel => levelOn('$root/downstream');

  /// The user may read `sys/audit` of the site on screen (its `tail` needs
  /// `config`).
  bool get readsAudit => can(Perm.config, '${root ?? ''}/sys/audit');

  /// The user may read [key]; false while `/api/me` is not read, as for a
  /// user with no grant on it (a trend locks the series, the gateway would
  /// refuse it anyway).
  bool mayRead(String key) => can(Perm.read, key);

  /// What the user lacks for a control that needs [level] on [key], or
  /// null when they have it (docs/studio.md §2 rule 8: shown, never
  /// hidden); `ui` words it.
  Lack? lacks(Perm level, String key) =>
      can(level, key) ? null : Lack(level, key.split('/').skip(2).join('/'));

  /// The highest level the session may use (`/api/me` `max`); null while
  /// `/api/me` is not read.
  Perm? get max => _state.site.max;

  /// Returns viewedVia
  List<String> get viewedVia => viewedViaOf(_state);

  /// The user logged in, by name (`user:olena@plant` → `olena`), else the
  /// user of the log-in form.
  String get userName =>
      userNameOf(_state.site.user ?? _state.login.user ?? '');

  /// The sites the switcher offers besides the one logged into.
  List<String> get otherSites => [
    for (final c in _state.site.choices)
      if (c.site != (_state.site.name ?? '')) c.site,
  ];
}

extension type SelectNodes(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveNodesAction>();

  /// Returns [IMap<String, NodeInfo>] table
  IMap<String, NodeInfo> get table => _state.nodes.table;

  /// Returns [NodeInfo] value by id
  NodeInfo byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.nodes.view;

  /// Returns expanded
  ISet<String> get expanded => _state.nodes.expanded;

  /// Returns selectedNode
  String? get selectedNode => _state.nodes.selectedNode;

  /// Returns results
  IMap<String, IList<String>> get results => _state.nodes.results;

  /// Returns tab
  ExplorerTab get tab => _state.nodes.tab;

  /// Returns action
  String? get action => _state.nodes.action;

  /// Returns historyRange
  HistoryRange get historyRange => _state.nodes.historyRange;

  /// Returns detail
  IMap<String, NodeDetail> get detail => _state.nodes.detail;

  /// Returns history
  IList<HistPoint> get history => _state.nodes.history;

  /// Returns historyKey
  String? get historyKey => _state.nodes.historyKey;

  /// Returns point
  String? get point => _state.nodes.point;

  /// Returns checked
  ISet<String> get checked => _state.nodes.checked;

  /// Returns anchor
  String? get anchor => _state.nodes.anchor;

  /// Returns treeFilter
  String get treeFilter => _state.nodes.treeFilter;

  /// Returns pointFilter
  String get pointFilter => _state.nodes.pointFilter;

  /// Returns marked
  ISet<String> get marked => _state.nodes.marked;

  /// Returns audit
  IList<AuditEntry> get audit => _state.nodes.audit;

  /// Returns listed
  ISet<String> get listed => _state.nodes.listed;

  /// Returns viewedPoint
  String? get viewedPoint => _state.nodes.viewedPoint;

  /// Returns historyFailed
  String? get historyFailed => _state.nodes.historyFailed;

  /// Returns listFailed
  IMap<String, String> get listFailed => _state.nodes.listFailed;

  /// Returns metaFailed
  IMap<String, String> get metaFailed => _state.nodes.metaFailed;

  /// Returns historyWindow
  HistWindow? get historyWindow => _state.nodes.historyWindow;

  /// Returns historyAt
  DateTime? get historyAt => _state.nodes.historyAt;

  /// Returns historyLoading
  bool get historyLoading =>
      _state.wait.isWaitingForType<RetrieveHistoryAction>();

  /// How many links the first list of the viewed site's `downstream` holds.
  int get linkCount {
    final prefix = '${SelectSite(_state).root}/downstream/';
    return _state.nodes.table.keys
        .where((k) => k.startsWith(prefix))
        .where((k) => !k.substring(prefix.length).contains('/'))
        .length;
  }

  /// Returns answers
  IMap<String, ActionAnswer> get answers => _state.nodes.answers;

  /// Returns watching
  IList<String>? get watching => _state.nodes.watching;

  /// The node menu: the node whose menu is open.
  String? get menu => _state.nodes.menu;

  /// A node menu waits for its node's `~meta`.
  bool get menuOpening => _state.wait.isWaitingForType<OpenNodeMenuAction>();

  /// Returns menuAsked
  String? get menuAsked => _state.nodes.menuAsked;

  /// Returns searchNodes
  List<SearchNode> get searchNodes => searchNodesOf(_state);
}

extension type SelectLive(AppState _state) {
  /// Returns values
  IMap<String, LiveValue> get values => _state.live.values;

  /// Returns watched
  IMap<String, int> get watched => _state.live.watched;

  /// Returns failed
  IMap<String, String> get failed => _state.live.failed;

  /// Returns lists
  IMap<String, int> get lists => _state.live.lists;
}

extension type SelectLinks(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveLinksAction>();

  /// Returns [IMap<String, LinkInfo>] table
  IMap<String, LinkInfo> get table => _state.links.table;

  /// Returns [LinkInfo] value by id
  LinkInfo byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.links.view;

  /// Returns tab
  LinksTab get tab => _state.links.tab;

  /// Returns selectedLink
  String? get selectedLink => _state.links.selectedLink;

  /// Returns log
  IList<String> get log => _state.links.log;

  /// Returns revisions
  IList<LinkRevision> get revisions => _state.links.revisions;

  /// Returns version
  String? get version => _state.links.version;

  /// A start, stop, remove, grant, deauthorize or rollback is running.
  bool get isActing =>
      _state.wait.isWaitingForType<StartLinkAction>() ||
      _state.wait.isWaitingForType<StopLinkAction>() ||
      _state.wait.isWaitingForType<RemoveLinkAction>() ||
      _state.wait.isWaitingForType<GrantLinkAction>() ||
      _state.wait.isWaitingForType<DeauthorizeLinkAction>() ||
      _state.wait.isWaitingForType<RollbackLinkParamsAction>();

  /// The log is being read.
  bool get isReadingLog => _state.wait.isWaitingForType<GetLinkLogAction>();

  /// The parameter revisions are being read.
  bool get isReadingHistory =>
      _state.wait.isWaitingForType<RetrieveLinkHistoryAction>();

  /// Returns updatesAvailable
  int get updatesAvailable => _state.links.updatesAvailable;
}

extension type SelectQuarantine(AppState _state) {
  /// Returns waiting value
  bool get isWaiting =>
      _state.wait.isWaitingForType<RetrieveQuarantineAction>();

  /// Returns [IMap<String, QuarantineEntry>] table
  IMap<String, QuarantineEntry> get table => _state.quarantine.table;

  /// Returns [QuarantineEntry] value by id
  QuarantineEntry byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.quarantine.view;

  /// Returns selectedEntry
  String? get selectedEntry => _state.quarantine.selectedEntry;

  /// Returns forms
  IMap<String, IList<ParamSpec>> get forms => _state.quarantine.forms;
}

extension type SelectPackages(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrievePackagesAction>();

  /// Returns [IMap<String, PackageInfo>] table
  IMap<String, PackageInfo> get table => _state.packages.table;

  /// Returns [PackageInfo] value by id
  PackageInfo byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.packages.view;
}

extension type SelectLinkInstall(AppState _state) {
  /// Returns step
  InstallStep get step => _state.linkInstall.step;

  /// Returns source
  InstallSource? get source => _state.linkInstall.source;

  /// Returns item
  String? get item => _state.linkInstall.item;

  /// Returns broker
  String? get broker => _state.linkInstall.broker;

  /// Returns mode
  LinkMode? get mode => _state.linkInstall.mode;

  /// Returns name
  String? get name => _state.linkInstall.name;

  /// Returns acceptRights
  bool get acceptRights => _state.linkInstall.acceptRights;

  /// Returns checks
  IList<PackageCheck> get checks => _state.linkInstall.checks;

  /// Returns message
  String? get message => _state.linkInstall.message;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<InstallLinkAction>();

  /// Returns path
  InstallPath get path => _state.linkInstall.path;

  /// Returns category
  CatalogCategory? get category => _state.linkInstall.category;

  /// Returns query
  String? get query => _state.linkInstall.query;

  /// Returns phase
  InstallPhase? get phase => _state.linkInstall.phase;

  /// Returns manifest
  String? get manifest => _state.linkInstall.manifest;

  /// Returns rights
  IList<RequestedRight>? get rights => _state.linkInstall.rights;

  /// Returns catalog
  IList<CatalogItem> get catalog => _state.linkInstall.catalog;

  /// Returns targets
  IList<InstallTarget> get targets => _state.linkInstall.targets;

  /// Returns method
  PackageMethod get method => _state.linkInstall.method;

  /// Returns refusedField
  InstallField? get refusedField => _state.linkInstall.refusedField;

  /// Returns refusedSaid
  String? get refusedSaid => _state.linkInstall.refusedSaid;

  /// Returns refusedStatus
  String? get refusedStatus => _state.linkInstall.refusedStatus;
}

extension type SelectPeers(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrievePeersAction>();

  /// Returns [IMap<String, Peer>] table
  IMap<String, Peer> get table => _state.peers.table;

  /// Returns [Peer] value by id
  Peer byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.peers.view;

  /// Returns selectedPeer
  SitePick? get selectedPeer => _state.peers.selectedPeer;

  /// Returns sitesKeys
  List<String> get sitesKeys => sitesKeysOf(_state);

  /// Returns sitePicked
  SitePick get sitePicked => sitePickedOf(_state);

  /// Returns sitesWaiting
  List<String> get sitesWaiting => sitesWaitingOf(_state);

  /// Returns sitesLack
  Lack? get sitesLack => sitesLackOf(_state);

  /// Returns siteMap
  List<SiteMapNode> get siteMap => siteMapOf(_state);

  /// Returns siteDetail
  SiteDetail? get siteDetail => siteDetailOf(_state);
}

extension type SelectFlows(AppState _state) {
  /// Returns search query string
  String? get query => _state.flows.query;

  /// Returns search results view
  IList<String> get view => _state.flows.view;

  /// Returns table
  IMap<String, FlowSummary> get table => _state.flows.table;

  /// Returns selectedFlow
  String? get selectedFlow => _state.flows.selectedFlow;

  /// Returns defs
  IMap<String, Object> get defs => _state.flows.defs;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveFlowsAction>();

  /// Returns blockTypes
  IList<NodeType> get blockTypes => _state.flows.blockTypes;

  /// Returns follow
  LiveSet? get follow => _state.flows.follow;

  /// The flows with their state, version, deployer and error from their
  /// live `~val` where Flows follows it.
  IMap<String, FlowSummary> get shownTable => _state.flows.table.map(
    (id, f) => MapEntry(
      id,
      liveFlow(
        f,
        _state.live.values['${SelectSite(_state).root}/dataflows/$id'],
      ),
    ),
  );

  /// The flows in their list's order, live while Flows follows them.
  List<FlowSummary> get shown {
    final table = shownTable;
    return [for (final id in _state.flows.view) ?table[id]];
  }

  /// The flow picked, live; null when none is.
  FlowSummary? get picked => switch (_state.flows.selectedFlow) {
    final id? => shownTable[id],
    null => null,
  };
}

extension type SelectFlowEditor(AppState _state) {
  /// Returns flowId
  String? get flowId => _state.flowEditor.flowId;

  /// Returns draft
  FlowDraft? get draft => _state.flowEditor.draft;

  /// Returns dirty
  bool get dirty => _state.flowEditor.dirty;

  /// Returns problems
  IList<FlowProblem> get problems => _state.flowEditor.problems;

  /// Returns selectedBlock
  String? get selectedBlock => _state.flowEditor.selectedBlock;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<DeployFlowAction>();

  /// Returns types
  IList<NodeType> get types => _state.flowEditor.types;

  /// Returns version
  int get version => _state.flowEditor.version;

  /// Returns palette
  PaletteTab get palette => _state.flowEditor.palette;

  /// Returns ports
  IMap<String, LiveValue> get ports => _state.flowEditor.ports;

  /// Returns deployed
  FlowDraft? get deployed => _state.flowEditor.deployed;

  /// Returns watchRefused
  Status? get watchRefused => _state.flowEditor.watchRefused;

  /// Returns previewPorts
  IMap<String, LiveValue> get previewPorts => _state.flowEditor.previewPorts;

  /// Returns previewSinks
  IMap<String, LiveValue> get previewSinks => _state.flowEditor.previewSinks;

  /// Returns previewError
  FlowProblem? get previewError => _state.flowEditor.previewError;

  /// Returns previewOff
  Status? get previewOff => _state.flowEditor.previewOff;

  /// Returns viewedField
  FieldAt? get viewedField => _state.flowEditor.viewedField;

  /// Returns selection
  ISet<String> get selection => _state.flowEditor.selection;

  /// Returns undo
  IList<FlowDraft> get undo => _state.flowEditor.undo;

  /// Returns redo
  IList<FlowDraft> get redo => _state.flowEditor.redo;

  /// Returns undoTag
  UndoTag? get undoTag => _state.flowEditor.undoTag;

  /// Returns clipboard
  String? get clipboard => _state.flowEditor.clipboard;

  /// Returns treeQuery
  String get treeQuery => _state.flowEditor.treeQuery;

  /// Returns scopePrompt
  String? get scopePrompt => _state.flowEditor.scopePrompt;

  /// Returns frames
  IList<FlowFrame> get frames => _state.flowEditor.frames;

  /// Returns library
  IList<BlockInfo> get library => _state.flowEditor.library;

  /// Returns libraryOff
  LibraryOff? get libraryOff => _state.flowEditor.libraryOff;

  /// Returns root
  FlowDraft? get root =>
      rootDraft(_state.flowEditor.frames, _state.flowEditor.draft);

  /// Returns allTypes
  IList<NodeType> get allTypes =>
      typesWithBlocks(_state.flowEditor.types, _state.flowEditor.draft);

  /// Returns caps
  FlowCaps get caps => flowCapsOf(
    _state.flowEditor.types,
    libraryOff: _state.flowEditor.libraryOff,
  );

  /// The editor of the route [routeId] (`newFlowId`: a new flow) as it is
  /// drawn, typed; the same view while nothing it shows changed.
  FlowView view(String routeId) => flowViewOf(_state, routeId);

  /// The route the editor was opened on (`newFlowId` for a new flow);
  /// null before it was opened.
  String? get route => _state.flowEditor.route;

  /// The blocks, fields and types of the editor's flow as the screen
  /// shows them (what an intent reads to act on a field).
  FlowBase get base => flowBaseOf(_state, route ?? newFlowId);
}

extension type SelectTasks(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveTasksAction>();

  /// Returns [IMap<String, AgentTask>] table
  IMap<String, AgentTask> get table => _state.tasks.table;

  /// Returns [AgentTask] value by id
  AgentTask byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.tasks.view;

  /// Returns selectedTask
  String? get selectedTask => _state.tasks.selectedTask;

  /// Returns events
  IMap<String, IList<TaskEvent>> get events => _state.tasks.events;

  /// Returns isAnswering
  bool get isAnswering => _state.wait.isWaitingForType<AnswerTaskAction>();
}

extension type SelectAssistant(AppState _state) {
  /// Returns draft
  String? get draft => _state.assistant.draft;

  /// Returns panel
  AssistantPanel get panel => _state.assistant.panel;

  /// Returns agent
  String? get agent => _state.assistant.agent;

  /// The agent link's id (`agent` of `wy/<site>/downstream/agent`).
  String? get agentId => _state.assistant.agent?.split('/').last;

  /// What the agent may do; null until its meta is read.
  AgentConfig? get config => _state.assistant.config;

  /// Who approves the agent's plans, as read (`write`, the link's own
  /// default, when the setting is absent); null when it is not known: the
  /// agent's settings did not read.
  ApprovalMode? get mode => _state.assistant.configInvalid
      ? null
      : (_state.assistant.config?.approval ?? .write);

  /// Who approves is not known: the agent's settings did not read.
  bool get modeUnknown => _state.assistant.configInvalid;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveAgentAction>();

  /// The agent is answering an ask.
  bool get isAsking => _state.wait.isWaitingForType<AskAgentAction>();

  /// Returns docs
  bool get docs => _state.assistant.docs;

  /// Returns unticked
  IMap<String, ISet<int>> get unticked => _state.assistant.unticked;

  /// Returns refusals
  IMap<String, ApprovalRefusal> get refusals => _state.assistant.refusals;

  /// Returns isApproving
  bool get isApproving => _state.wait.isWaitingForType<ApproveTaskAction>();

  /// Returns picks
  IMap<String, ISet<String>> get picks => _state.assistant.picks;

  /// Returns shown
  bool get shown => _state.assistant.shown;

  /// Returns watched
  IList<String> get watched => _state.assistant.watched;

  /// Returns rowPicks
  IMap<String, ISet<String>> get rowPicks => _state.assistant.rowPicks;

  /// Returns chips
  IList<String> get chips => _state.assistant.chips;

  /// Returns revealed
  IMap<String, ISet<int>> get revealed => _state.assistant.revealed;

  /// Returns drawer
  bool get drawer => _state.assistant.drawer;

  /// Where the agent may propose changes, as read.
  IList<String> get prefixes =>
      _state.assistant.config?.prefixes ?? const IListConst([]);

  /// Which keys the agent reads is known: its settings were read. Before
  /// that every key is offered as context.
  bool get readsKnown =>
      _state.assistant.config != null &&
      _state.assistant.config != const AgentConfig();

  /// Returns drawerWatched
  IList<String> get drawerWatched => _state.assistant.drawerWatched;

  /// Returns drawerShown
  bool get drawerShown => _state.assistant.drawerShown;

  /// Returns secrets
  ISet<String>? get secrets => _state.assistant.secrets;

  /// Returns timelineKey
  String? get timelineKey => _state.assistant.timelineKey;

  /// Returns timelineAudit
  IList<AuditEntry> get timelineAudit => _state.assistant.timelineAudit;
}

extension type SelectChanges(AppState _state) {
  /// Returns [IMap<String, StagedChange>] table
  IMap<String, StagedChange> get table => _state.changes.table;

  /// Returns [StagedChange] value by id
  StagedChange byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.changes.view;

  /// Returns open
  bool get open => _state.changes.open;

  /// Returns message
  CallRefusal? get message => _state.changes.message;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<ApplyChangesAction>();

  /// Returns reviewCards
  List<ReviewCard> get reviewCards => reviewCardsOf(_state);

  /// Returns reviewAudit
  String get reviewAudit => reviewAuditOf(_state);
}

extension type SelectHistorian(AppState _state) {
  /// Returns groups
  IList<WatchGroup> get groups => _state.historian.groups;

  /// Returns selected
  String? get selected => _state.historian.selected;

  /// Returns range
  TrendRange get range => _state.historian.range;

  /// Returns series
  IMap<String, IList<HistPoint>> get series => _state.historian.series;

  /// Returns stats
  IMap<String, String> get stats => _state.historian.stats;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveHistorianAction>();

  /// Returns points
  IList<String> get points => _state.historian.points;

  /// Returns follow
  LiveSet? get follow => _state.historian.follow;

  /// The watch groups with their settings from the live values History
  /// follows (`sys/history/*/*`).
  IList<WatchGroup> get shownGroups => liveGroups(
    _state.historian.groups,
    '${SelectSite(_state).root}/sys/history',
    _state.live.values,
  );

  /// The historian's values (rows written, size, oldest day …), live while
  /// History follows `sys/history/*`.
  IMap<String, String> get shownStats => liveStats(
    _state.historian.stats,
    '${SelectSite(_state).root}/sys/history',
    _state.live.values,
  );

  /// Returns window
  HistWindow? get window => _state.historian.window;

  /// Returns detail
  HistDetail? get detail => _state.historian.detail;

  /// Returns low
  IMap<String, IList<HistPoint>> get low => _state.historian.low;

  /// Returns high
  IMap<String, IList<HistPoint>> get high => _state.historian.high;

  /// Returns hidden
  ISet<String> get hidden => _state.historian.hidden;

  /// Returns trendGen
  int get trendGen => _state.historian.trendGen;

  /// Returns seriesAt
  DateTime? get seriesAt => _state.historian.seriesAt;

  /// The trend's range is being read (spec trend.md §6: a skeleton until
  /// it has rows).
  bool get seriesLoading =>
      _state.wait.isWaitingForType<RetrieveSeriesAction>();

  /// The trend's window is being read finer (the bar over the plot).
  bool get windowLoading =>
      _state.wait.isWaitingForType<LoadTrendWindowAction>();

  /// Returns trendSpan
  TrendSpan get trendSpan => historyRangeOf(_state);

  /// Returns trend
  HistoryTrend? get trend => historyTrendOf(_state);

  /// Returns shownGroup
  WatchGroup? get shownGroup => shownGroupOf(_state);

  /// Returns pickedWatch
  String? get pickedWatch => pickedWatchOf(_state);

  /// Returns historianStats
  HistorianStats get historianStats => historianStatsOf(_state);

  /// The key of [node] for History's calls.
  String keyOf(HistoryNode node) => historyKeyOf(_state, node);
}

extension type SelectAccess(AppState _state) {
  /// Returns users
  IList<UserInfo> get users => _state.access.users;

  /// Returns grants
  IList<RoleGrant> get grants => _state.access.grants;

  /// Returns audit
  IList<AuditLine> get audit => _state.access.audit;

  /// Returns selected
  String? get selected => _state.access.selected;

  /// Returns tab
  AccessTab get tab => _state.access.tab;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveAccessAction>();

  /// Returns shown
  bool get shown => _state.access.shown;

  /// The user picked, as `/api/users` gives them; null when none is.
  UserInfo? get pickedUser => _state.access.users
      .where((u) => u.name == _state.access.selected)
      .firstOrNull;

  /// The grants of [user]'s roles.
  List<RoleGrant> grantsOf(UserInfo user) => [
    for (final g in _state.access.grants)
      if (user.roles.contains(g.subject)) g,
  ];

  /// The roles a user may be given: the subjects of the gateway's grants,
  /// or the four of a fresh gateway when it lists none.
  List<String> get roleNames {
    final roles = {
      for (final g in _state.access.grants)
        if (g.source == GrantSource.gateway) g.subject,
    };
    return roles.isEmpty
        ? const ['admin', 'engineer', 'operator', 'viewer']
        : roles.toList();
  }
}

extension type SelectSystem(AppState _state) {
  /// Returns log
  IList<LogLine> get log => _state.system.log;

  /// Returns logLevel
  LogLevel? get logLevel => _state.system.logLevel;

  /// Returns filter
  String? get filter => _state.system.filter;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveSystemLogAction>();

  /// Returns tab
  SystemTab get tab => _state.system.tab;

  /// Returns measure
  TrafficMeasure get measure => _state.system.measure;

  /// Returns source
  String? get source => _state.system.source;

  /// Returns lines
  int get lines => _state.system.lines;

  /// Returns auto
  bool get auto => _state.system.auto;

  /// Returns shown
  bool get shown => _state.system.shown;

  /// Returns logError
  LogReadError? get logError => _state.system.logError;

  /// Returns samples
  IList<TrafficSample> get samples => _state.system.samples;

  /// Returns trafficRoot
  String? get trafficRoot => _state.system.trafficRoot;

  /// Returns profiles
  IList<ProfileInfo> get profiles => _state.system.profiles;

  /// Returns profilesNote
  CallRefusal? get profilesNote => _state.system.profilesNote;

  /// Returns aclSeen
  int? get aclSeen => _state.system.aclSeen;

  /// Returns about
  IMap<String, String> get about => _state.system.about;

  /// Returns units
  IMap<String, String> get units => _state.system.units;

  /// Returns isActing
  bool get isActing =>
      _state.wait.isWaitingForType<ClearConnsAction>() ||
      _state.wait.isWaitingForType<PutProfileAction>() ||
      _state.wait.isWaitingForType<RemoveProfileAction>();

  /// Returns around
  String? get around => _state.system.around;

  /// Returns trafficWindow
  HistWindow? get trafficWindow => _state.system.trafficWindow;
}

extension type SelectPanels(AppState _state) {
  /// Returns widths
  IMap<PanelSlot, double> get widths => _state.panels.widths;
}

extension type SelectWindow(AppState _state) {
  /// Returns maximized
  bool get maximized => _state.window.maximized;

  /// Returns fullScreen
  bool get fullScreen => _state.window.fullScreen;

  /// Returns left
  double? get left => _state.window.left;

  /// Returns top
  double? get top => _state.window.top;

  /// Returns width
  double? get width => _state.window.width;

  /// Returns height
  double? get height => _state.window.height;
}

extension type SelectProblems(AppState _state) {
  /// Returns items
  IList<StudioError> get items => _state.problems.items;

  /// Returns unread
  int get unread => _state.problems.unread;

  /// Returns open
  bool get open => _state.problems.open;

  /// Returns toasts
  IList<int> get toasts => _state.problems.toasts;

  /// Returns notices
  IList<StudioNotice> get notices => _state.problems.notices;

  /// Returns pill
  ProblemsCount? get pill => problemsCountOf(_state);

  /// Returns shownToasts
  List<Toast> get shownToasts => toastsOf(_state);
}

extension type SelectUpdates(AppState _state) {
  /// Returns package
  String? get package => _state.updates.package;

  /// Returns view
  UpdateView get view => _state.updates.view;

  /// Returns takePoint
  bool get takePoint => _state.updates.takePoint;

  /// Returns autoRollback
  bool get autoRollback => _state.updates.autoRollback;

  /// Returns acceptNew
  bool get acceptNew => _state.updates.acceptNew;

  /// Returns asks
  String? get asks => _state.updates.asks;

  /// Returns message
  String? get message => _state.updates.message;

  /// Returns seenAt
  int get seenAt => _state.updates.seenAt;

  /// Returns queue
  IList<String> get queue => _state.updates.queue;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<UpdatePackageAction>();

  /// Returns isRollingBack
  bool get isRollingBack =>
      _state.wait.isWaitingForType<RollbackPackageAction>();
}

extension type SelectBackups(AppState _state) {
  /// Returns table
  IMap<String, BackupJob> get table => _state.backups.table;

  /// Returns view
  IList<String> get view => _state.backups.view;

  /// Returns exportSecrets
  bool get exportSecrets => _state.backups.exportSecrets;

  /// Returns sendLinks
  IList<SendLink> get sendLinks => _state.backups.sendLinks;

  /// Returns sections
  IList<String> get sections => _state.backups.sections;

  /// Returns keepDays
  int get keepDays => _state.backups.keepDays;

  /// Returns stage
  String? get stage => _state.backups.stage;

  /// Returns link
  String? get link => _state.backups.link;

  /// Returns chosen
  ISet<String> get chosen => _state.backups.chosen;

  /// Returns historyDays
  int? get historyDays => _state.backups.historyDays;

  /// Returns offLinks
  ISet<String> get offLinks => _state.backups.offLinks;

  /// Returns where
  String get where => _state.backups.where;

  /// Returns sendLink
  String? get sendLink => _state.backups.sendLink;

  /// Returns sendConnection
  String? get sendConnection => _state.backups.sendConnection;

  /// Returns sendPath
  String? get sendPath => _state.backups.sendPath;

  /// Returns connections
  IList<String> get connections => _state.backups.connections;

  /// Returns estimate
  IMap<String, int> get estimate => _state.backups.estimate;

  /// Returns job
  String? get job => _state.backups.job;

  /// Returns downloading
  String? get downloading => _state.backups.downloading;

  /// Returns downloaded
  int get downloaded => _state.backups.downloaded;

  /// Returns upload
  String? get upload => _state.backups.upload;

  /// Returns uploadName
  String? get uploadName => _state.backups.uploadName;

  /// Returns uploadSize
  int get uploadSize => _state.backups.uploadSize;

  /// Returns uploaded
  int get uploaded => _state.backups.uploaded;

  /// Returns check
  RestoreCheck? get check => _state.backups.check;

  /// Returns mode
  String get mode => _state.backups.mode;

  /// Returns replaceKeys
  bool get replaceKeys => _state.backups.replaceKeys;

  /// Returns acceptRights
  bool get acceptRights => _state.backups.acceptRights;

  /// Returns result
  String? get result => _state.backups.result;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveBackupsAction>();

  /// Returns saved
  IMap<String, String> get saved => _state.backups.saved;

  /// Returns opening
  int get opening => _state.backups.opening;
}

extension type SelectBrokerUpdate(AppState _state) {
  /// Returns stage
  String? get stage => _state.brokerUpdate.stage;

  /// Returns confirm
  String get confirm => _state.brokerUpdate.confirm;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<UpdateBrokerAction>();
}

extension type SelectDevice(AppState _state) {
  /// Returns available
  bool get available => _state.device.available;

  /// Returns kind
  KeyKind get kind => _state.device.kind;

  /// Returns name
  String? get name => _state.device.name;

  /// Returns keyId
  String? get keyId => _state.device.keyId;

  /// Returns deviceId
  String? get deviceId => _state.device.deviceId;

  /// Returns added
  int get added => _state.device.added;

  /// Returns lastUsed
  int get lastUsed => _state.device.lastUsed;

  /// Returns keySite
  String? get keySite => _state.device.keySite;

  /// Returns stale
  bool get stale => _state.device.stale;

  /// Returns lockAfter
  int get lockAfter => _state.device.lockAfter;

  /// Returns dontAsk
  bool get dontAsk => _state.device.dontAsk;

  /// Returns offered
  bool get offered => _state.device.offered;

  /// Returns noticed
  bool get noticed => _state.device.noticed;

  /// Returns policy
  DevicePolicy? get policy => _state.device.policy;

  /// Returns stage
  UnlockStage get stage => _state.device.stage;

  /// Returns refusal
  UnlockRefusal? get refusal => _state.device.refusal;

  /// Why the page fell back to the password, the key kept.
  UnlockFallback? get fallback => _state.device.fallback;

  /// Returns reEnable
  bool get reEnable => _state.device.reEnable;

  /// Returns autoPrompted
  bool get autoPrompted => _state.device.autoPrompted;

  /// Returns locked
  bool get locked => _state.device.locked;

  /// Why the idle lock is still on after a try.
  LockError? get lockError => _state.device.lockError;

  /// Returns stepUp
  StepUpRequest? get stepUp => _state.device.stepUp;

  /// Returns devices
  IList<GatewayDevice> get devices => _state.device.devices;

  /// Returns userDevices
  IMap<String, IList<GatewayDevice>> get userDevices =>
      _state.device.userDevices;

  /// Returns needPassword
  bool get needPassword => _state.device.needPassword;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<LoadDeviceAction>();

  /// Returns keyRole
  String? get keyRole => _state.device.keyRole;

  /// This computer unlocks with its key: a device record and a key, not
  /// stale.
  bool get unlockOn =>
      _state.device.deviceId != null &&
      _state.device.keyId != null &&
      !_state.device.stale;

  /// The unlock switch can be used: a biometric is here and the gateway's
  /// policy (when known) has devices on.
  bool get unlockAllowed =>
      _state.device.available && (_state.device.policy?.enabled ?? true);

  /// The gateway asks for a fresh confirmation before a config change
  /// (`gateway.devices.step_up: config`).
  bool get confirmsConfig => _state.device.policy?.stepUp == StepUp.config;

  /// The longest idle lock the gateway allows, in minutes (30 when not
  /// told).
  int get lockMaxMin => _state.device.policy?.idleLockMaxMin ?? 30;

  /// The device keys a user may have on the gateway (5 when not told).
  int get maxPerUser => _state.device.policy?.maxPerUser ?? 5;

  /// Every how many days the gateway asks for the password again (30 when
  /// not told).
  int get passwordEveryDays => _state.device.policy?.passwordEveryDays ?? 30;

  /// The site the offer names: the one logged into, else the key's.
  String get offerSite => _state.site.name ?? _state.device.keySite ?? '';

  /// This user's device records as rows of Account › Security at [now].
  IList<DeviceRow> rowsAt(DateTime now) => [
    for (final d in _state.device.devices)
      deviceRowOf(d, _state.device.deviceId, now),
  ].lock;

  /// The devices of [user] (Access › Users) as rows at [now].
  IList<DeviceRow> userRowsAt(String user, DateTime now) => [
    for (final d
        in _state.device.userDevices[user] ??
            const IListConst<GatewayDevice>([]))
      deviceRowOf(d, _state.device.deviceId, now),
  ].lock;

  /// When this computer's key was made; null when not known.
  DateTime? get keyAddedAt => momentOf(_state.device.added);

  /// The unlock switch is being turned on or off.
  bool get isSettingUnlock =>
      _state.wait.isWaitingForType<SetDeviceUnlockAction>();

  /// Returns passwordRefused
  bool get passwordRefused => _state.device.passwordRefused;

  /// The key here can sign: a biometric, a key, not stale.
  bool get keyUsable =>
      _state.device.available &&
      _state.device.keyId != null &&
      !_state.device.stale;

  /// The key or the password of the lock is being checked.
  bool get isUnlocking =>
      _state.wait.isWaitingForType<UnlockWithDeviceAction>() ||
      _state.wait.isWaitingForType<UnlockWithPasswordAction>();

  /// A key is being made and registered.
  bool get isEnabling => _state.wait.isWaitingForType<EnableDeviceAction>();

  /// `Turn <name> on again after I log in` is offered: after `changed`
  /// and `signedOut`, not after `devices_off` (nothing to turn on) nor
  /// `password_due` (the key stays), and only with a biometric here.
  bool get offersReEnable {
    final d = _state.device;
    final after =
        d.stage == UnlockStage.changed ||
        (d.stage == UnlockStage.signedOut &&
            d.refusal != UnlockRefusal.devicesOff &&
            d.refusal != UnlockRefusal.passwordDue);
    return after && d.available;
  }

  /// The footer names the key (`Key in … · added …`), not the TLS line:
  /// a key that still stands.
  bool get keyShown =>
      _state.device.keyId != null &&
      _state.device.stage != UnlockStage.changed &&
      _state.device.stage != UnlockStage.signedOut;

  /// When the key last unlocked; null for none (a password log-in).
  DateTime? get lastUsedAt =>
      _state.device.keyId == null ? null : momentOf(_state.device.lastUsed);
}

extension type SelectDiscovery(AppState _state) {
  /// Returns open
  bool get open => _state.discovery.open;

  /// Returns scanning
  bool get scanning => _state.discovery.scanning;

  /// Returns ended
  bool get ended => _state.discovery.ended;

  /// Returns scan
  int get scan => _state.discovery.scan;

  /// Returns found
  IMap<String, FoundGateway> get found => _state.discovery.found;

  /// Returns pins
  IMap<String, CaPin> get pins => _state.discovery.pins;

  /// Returns trustPending
  String? get trustPending => _state.discovery.trustPending;

  /// Why the last trust pinned nothing.
  TrustRefusal? get trustRefused => _state.discovery.trustRefused;

  /// Returns picked
  String? get picked => _state.discovery.picked;

  /// Returns network
  String? get network => _state.discovery.network;

  /// Returns subnet
  String? get subnet => _state.discovery.subnet;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<TrustGatewayAction>();

  /// Returns range
  String? get range => _state.discovery.range;

  /// Returns rangePort
  String? get rangePort => _state.discovery.rangePort;

  /// Returns probing
  bool get probing => _state.discovery.probing;

  /// The row whose CA waits for the person's check; null for none.
  FoundGateway? get pendingRow => switch (_state.discovery.trustPending) {
    final p? => _state.discovery.found[p],
    null => null,
  };

  /// The row picked; null for none.
  FoundGateway? get pickedRow => switch (_state.discovery.picked) {
    final p? => _state.discovery.found[p],
    null => null,
  };

  /// The picked row while the gateway field still holds its URL.
  FoundGateway? get pickedInField {
    final row = pickedRow;
    final field = GatewayField.of(_state.login.gateway).mainUri;
    return row?.url != null &&
            parseGateways(row!.url!).firstOrNull?.origin == field?.origin
        ? row
        : null;
  }

  /// The CA code of the row whose trust waits, in groups of 4: computed
  /// here from the CA's bytes when the row was made, never the gateway's
  /// claim.
  List<String> get pendingCode => codeGroups(pendingRow?.code ?? '');

  /// The host the pending row's certificate must name.
  String get pendingHost => switch (pendingRow?.url) {
    final u? => Uri.tryParse(u)?.host ?? '',
    null => '',
  };

  /// The found rows at [now], usable first, then by site.
  List<FoundRow> rowsAt(DateTime now) => foundRowsAt(
    _state.discovery.found.values,
    recent: _state.login.recent,
    pins: _state.discovery.pins,
    picked: _state.discovery.picked,
    now: now,
  );

  /// The range *Probe a range* uses: what was typed, else the /24 around
  /// this computer.
  String get rangeText =>
      _state.discovery.range ?? _state.discovery.subnet ?? '';

  /// The port *Probe a range* uses until one is typed.
  int get defaultProbePort => defaultProbePortOf(_state.login.gateway);

  /// The port field as it reads: what was typed, else the default port.
  String get portText => _state.discovery.rangePort ?? '$defaultProbePort';

  /// What is wrong with the range; null when it can be probed.
  RangeFault? get rangeFault => rangeFaultOf(rangeText);

  /// The port to probe; null while what is typed is not one.
  int? get probePort => switch (_state.discovery.rangePort) {
    final typed? => probePortOf(typed),
    null => defaultProbePort,
  };
}

extension type SelectClock(AppState _state) {
  /// The time screens show their rows at (`TickClockAction`); the start of
  /// the epoch before the first tick.
  DateTime get now => _state.clock.now ?? _epoch;
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
