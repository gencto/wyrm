import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/ask_agent_action.dart';
import 'package:business/redux/assistant/actions/follow_drawer_action.dart';
import 'package:business/redux/assistant/actions/pick_suggestion_action.dart';
import 'package:business/redux/assistant/actions/send_ask_action.dart';
import 'package:business/redux/assistant/actions/set_chip_action.dart';
import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/assistant/actions/set_option_pick_action.dart';
import 'package:business/redux/assistant/actions/set_panel_action.dart';
import 'package:business/redux/assistant/actions/set_row_pick_action.dart';
import 'package:business/redux/assistant/actions/set_step_reveal_action.dart';
import 'package:business/redux/assistant/actions/set_step_tick_action.dart';
import 'package:business/redux/assistant/actions/set_watched_action.dart';
import 'package:business/redux/assistant/actions/show_assistant_action.dart';
import 'package:business/redux/assistant/actions/show_drawer_action.dart';
import 'package:business/redux/assistant/actions/stage_agent_param_action.dart';
import 'package:business/redux/nodes/actions/open_trend_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/set_history_window_action.dart';
import 'package:business/redux/nodes/actions/zoom_history_action.dart';
import 'package:business/redux/tasks/actions/answer_task_action.dart';
import 'package:business/redux/tasks/actions/approve_task_action.dart';
import 'package:business/redux/tasks/actions/new_task_action.dart';
import 'package:business/redux/tasks/actions/open_task_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/assistant_composer.dart';
import 'package:ui/assistant/assistant_drawer.dart';
import 'package:ui/assistant/choices_card.dart';
import 'package:ui/assistant/task_badge.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/assistant_page.dart';

import '../common/tab_visibility.dart';
import '../dialogs/assistant_dialogs.dart';
import '../mappers/assistant_mappers.dart';
import '../mappers/assistant_shown.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';
import '../navigation/go_after_action.dart';

/// The Assistant tab (spec `assistant.md`): the agent's tasks, the selected
/// task's conversation and cards, the ask box, *This task* and *What it may
/// do*. It reads what is drawn from `app/lib/mappers/assistant_shown.dart`
/// (decided in `business`, mapped there, the widgets word it) and starts
/// one action per intent; a control that asks first opens its dialog from
/// `assistant_dialogs.dart` (studio-rules §3, §4, §5, §9).
@RoutePage()
class AssistantPageConnector extends StatelessWidget {
  const AssistantPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    // the keys the Result card shows changed: watched again, in one action
    // that keeps none while the tab is hidden
    onWillChange: (context, store, before, now) {
      if (!_same(before.shown.watch, now.shown.watch)) {
        store.dispatchSync(SetWatchedAction.shown());
      }
    },
    builder: (context, vm) {
      final shown = vm.shown;
      return TabVisibility(
        onShow: vm.onShow,
        onHide: vm.onHide,
        child: AssistantPage(
          sections: shown.sections.unlockView,
          onNew: vm.onNew,
          onTask: vm.onTask,
          agent: shown.agent,
          noAgent: shown.noAgent,
          title: shown.title,
          badge: shown.badge,
          taskId: shown.taskId,
          events: shown.events.unlockView,
          plan: shown.plan,
          onTick: vm.ticks?.onToggle,
          onFix: vm.onPickSuggestion,
          onReveal: vm.onReveal,
          run: shown.run,
          result: shown.result,
          more: shown.more.unlockView,
          onRow: vm.rows?.onToggle,
          onMore: vm.onPickSuggestion,
          stopped: shown.stopped,
          onWay: vm.onPickSuggestion,
          choices: shown.choices,
          onPick: switch (vm.onPick) {
            final pick? => (q, o) => pick(OptionPick(q, o)),
            null => null,
          },
          onAnswer: vm.onAnswer,
          card: shown.card,
          // a control that asks first opens its dialog; the others start
          // their action at once
          onButton: (b) => pressTaskButton(
            context,
            b,
            task: shown.taskId,
            onStart: vm.onStart,
          ),
          composer: shown.composer,
          onDraft: vm.onDraft,
          onAsk: vm.onAsk,
          onChipRemove: vm.onChipRemove,
          onAddChip: () => pickContextKey(context),
          panel: shown.panel,
          onPanel: vm.onPanel,
          facts: shown.facts,
          reads: shown.reads.unlockView,
          rights: shown.rights,
          onMode: vm.onMode,
          onRemovePrefix: vm.onRemovePrefix,
          onAddPrefix: () => addPrefix(context, root: shown.root),
          onAddAgent: vm.onAddAgent,
        ),
      );
    },
  );
}

bool _same(IList<String> a, IList<String> b) =>
    a.length == b.length && a.every(b.contains);

/// The Assistant as a drawer over Explorer (⌘J, spec `assistant.md` §5):
/// the same task and cards as the tab, from the same mapping.
class AssistantDrawerConnector extends StatelessWidget {
  const AssistantDrawerConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this, drawer: true),
    // the selected point's timeline
    onInitialBuild: (context, store, vm) =>
        store.dispatch(FollowDrawerAction()),
    // the finding nodes, watched while the drawer is shown, and the
    // timeline of Explorer's point
    onWillChange: (context, store, before, now) =>
        !_same(before.shown.findingKeys, now.shown.findingKeys) ||
            before.shown.timelinePoint != now.shown.timelinePoint
        ? store.dispatch(FollowDrawerAction())
        : null,
    // the drawer is in Explorer's page: shown while Explorer's tab is the
    // active one and the drawer is open (ADR 0037 rule 5)
    builder: (context, vm) {
      final shown = vm.shown;
      return TabVisibility(
        onShow: vm.onShow,
        onHide: vm.onHide,
        child: AssistantDrawer(
          taskId: shown.taskId,
          onOpenFull: vm.onOpenFull,
          onClose: vm.onCloseDrawer,
          events: shown.events.unlockView,
          choices: shown.choices,
          onPick: switch (vm.onPick) {
            final pick? => (q, o) => pick(OptionPick(q, o)),
            null => null,
          },
          onAnswer: vm.onAnswer,
          plan: shown.plan,
          onTick: vm.ticks?.onToggle,
          onFix: vm.onPickSuggestion,
          onReveal: vm.onReveal,
          run: shown.run,
          stopped: shown.stopped,
          onWay: vm.onPickSuggestion,
          card: shown.card,
          second: shown.second,
          onSecond: () =>
              pressSecond(context, shown.second, vm.onPickSuggestion),
          onNewTask: vm.onNewTask,
          onButton: (b) => pressTaskButton(
            context,
            b,
            task: shown.taskId,
            onStart: vm.onStart,
          ),
          noAgent: shown.noAgent,
          found: shown.found,
          onTimelineWindow: (a, b) => vm.onTimelineWindow(TrendWindow(a, b)),
          onTimelineReset: vm.onTimelineReset,
          composer: AssistantComposer(
            vm: shown.composer,
            onDraft: vm.onDraft,
            onAsk: vm.onAsk,
            onChipRemove: vm.onChipRemove,
            onAddChip: () => pickContextKey(context),
          ),
        ),
      );
    },
  );
}

/// Factory that creates a view-model for the StoreConnector (of the tab
/// and, with [drawer], of the drawer).
class _Factory extends VmFactory<AppState, StatelessWidget, _Vm>
    with Selectors {
  _Factory(super._connector, {this.drawer = false});

  final bool drawer;

  /// What is drawn comes from [assistantShownOf], the same object while
  /// nothing it shows changed. A callback names what was done, with only
  /// what [AssistantShown] holds (so a view-model kept as equal keeps
  /// callbacks that are still right); an action reads the rest when it
  /// runs.
  @override
  _Vm fromStore() {
    final shown = assistantShownOf(state, waiting, drawer: drawer);
    final id = shown.taskId;
    final ticked = shown.tickedSteps;
    final picked = shown.pickedRows;
    return _Vm(
      shown: shown,
      ticks: id == null || ticked == null
          ? null
          : ToggleVm(
              selected: ticked.toISet(),
              onToggle: (n, {required on}) =>
                  dispatchSync(SetStepTickAction(id, n, ticked: on)),
            ),
      rows: id == null || picked == null
          ? null
          : ToggleVm(
              selected: picked,
              onToggle: (row, {required on}) => dispatchSync(
                SetRowPickAction(id, row.suggestion, row.key, on: on),
              ),
            ),
      onPick: id == null
          ? null
          : (p) => dispatchSync(
              SetOptionPickAction.of(id, p.question, p.option),
            ),
      onAnswer: id == null ? null : () => dispatch(AnswerTaskAction(id)),
      onPickSuggestion: id == null
          ? null
          : (s) => dispatch(PickSuggestionAction(id, s)),
      onReveal: id == null
          ? null
          : (n) => dispatchSync(SetStepRevealAction.toggle(id, n)),
      // a button of the card that starts its action at once: what it names
      // (a task, a node, a point) is on the button
      onStart: (b) => switch (b.button) {
        // what is on screen now: the plan and the ticks as shown
        TaskButton.approve => switch (id) {
          final id? => dispatch(
            ApproveTaskAction(
              id,
              plan: shown.planHash,
              steps: (ticked ?? const IListConst([])).unlockView,
            ),
          ),
          null => null,
        },
        TaskButton.followUp => dispatch(
          AskAgentAction(text: b.says, parent: b.name),
        ),
        TaskButton.replacement => dispatch(OpenTaskAction(b.name)),
        TaskButton.explorer => dispatch(
          GoAfterAction(const ExplorerRoute(), [SelectNodeAction(b.name)]),
        ),
        TaskButton.trend => dispatch(
          GoAfterAction(const ExplorerRoute(), [
            SetDrawerAction(open: false),
            OpenTrendAction(b.name),
          ]),
        ),
        // these ask first: their dialogs start them
        TaskButton.reject || TaskButton.cancel || TaskButton.save => null,
      },
      onTimelineWindow: (w) => dispatchSync(ZoomHistoryAction(w.start, w.end)),
      onTimelineReset: () => dispatchSync(SetHistoryWindowAction(null)),
      onDraft: (text) => dispatchSync(SetDraftAction(text)),
      onAsk: () => dispatch(SendAskAction(drawer: drawer)),
      onChipRemove: (k) => dispatchSync(SetChipAction(k, on: false)),
      onPanel: (p) => dispatch(SetPanelAction(p.panel)),
      onMode: (m) => switch (m.domain) {
        final mode? => dispatch(StageAgentParamAction.mode(mode)),
        null => null,
      },
      onRemovePrefix: (p) => dispatch(StageAgentParamAction.removePrefix(p)),
      onAddAgent: () => dispatch(GoAction.push(const LinkInstallRoute())),
      onShow: () => dispatch(
        drawer
            ? ShowDrawerAction(shown: true)
            : ShowAssistantAction(shown: true),
      ),
      onHide: () => dispatch(
        drawer
            ? ShowDrawerAction(shown: false)
            : ShowAssistantAction(shown: false),
      ),
      onNew: () => dispatchSync(NewTaskAction()),
      onNewTask: id == null
          ? null
          : () => dispatchSync(SetSelectedTaskAction(null)),
      onTask: (task) => dispatch(OpenTaskAction(task)),
      onOpenFull: id == null
          ? null
          : () => dispatch(
              GoAfterAction(const AssistantRoute(), [
                SetDrawerAction(open: false),
              ]),
            ),
      onCloseDrawer: () => dispatchSync(SetDrawerAction(open: false)),
    );
  }
}

/// What the Assistant draws ([shown], compared, with the ticks made of it)
/// and what it starts (not compared, but for whether it is there).
class _Vm extends Vm {
  _Vm({
    required this.shown,
    required this.ticks,
    required this.rows,
    required this.onPick,
    required this.onAnswer,
    required this.onPickSuggestion,
    required this.onReveal,
    required this.onStart,
    required this.onTimelineWindow,
    required this.onTimelineReset,
    required this.onDraft,
    required this.onAsk,
    required this.onChipRemove,
    required this.onPanel,
    required this.onMode,
    required this.onRemovePrefix,
    required this.onAddAgent,
    required this.onShow,
    required this.onHide,
    required this.onNew,
    required this.onNewTask,
    required this.onTask,
    required this.onOpenFull,
    required this.onCloseDrawer,
  }) : super(
         equals: [
           shown,
           ticks,
           rows,
           onNewTask != null,
           onOpenFull != null,
           onPick != null,
           onAnswer != null,
           onPickSuggestion != null,
           onReveal != null,
         ],
       );

  /// Everything drawn, as `ui` render models.
  final AssistantShown shown;

  /// The ticks of the plan; null: the plan is only shown.
  final ToggleVm<int>? ticks;

  /// The ticked rows of *Same for more units?*.
  final ToggleVm<MoreRowRef>? rows;

  /// An option of a question was picked.
  final ValueChanged<OptionPick>? onPick;
  final VoidCallback? onAnswer;

  /// A suggestion (a fix, a way out, more units) of the task was picked.
  final ValueChanged<String>? onPickSuggestion;
  final ValueChanged<int>? onReveal;

  /// A button of the task's card that starts its action at once.
  final ValueChanged<TaskButtonVm> onStart;
  final ValueChanged<TrendWindow> onTimelineWindow;
  final VoidCallback onTimelineReset;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;
  final ValueChanged<String> onChipRemove;
  final ValueChanged<AssistantTab> onPanel;
  final ValueChanged<AgentModeVm> onMode;
  final ValueChanged<String> onRemovePrefix;
  final VoidCallback onAddAgent;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onNew;
  final VoidCallback? onNewTask;
  final ValueChanged<String> onTask;
  final VoidCallback? onOpenFull;
  final VoidCallback onCloseDrawer;
}
