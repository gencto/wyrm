import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../alerts/notice.dart';
import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/answer_list.dart';
import '../containers/catalog_card.dart';
import '../containers/choice_card.dart';
import '../containers/fact_grid.dart';
import '../containers/section_label.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../indicators/check_list.dart';
import '../indicators/step_rail.dart';
import '../models/link_run_mode.dart';
import '../models/tone.dart';
import '../overlays/log_view.dart';
import '../shell/window_bar.dart';
import '../shell/wyrm_logo.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'link_install_data.dart';

export 'link_install_data.dart';

/// Board *Add a link* (rows Official and Custom): steps on the left, the
/// step in the middle, the answers on the right, Back and Continue below.
class LinkInstallPage extends StatelessWidget {
  const LinkInstallPage({
    required this.vm,
    required this.onClose,
    this.onFrom,
    this.onCategory,
    this.onQuery,
    this.onItem,
    this.onMethod,
    this.onPickFile,
    this.onUrl,
    this.onRef,
    this.onBroker,
    this.onMode,
    this.onName,
    this.onAccept,
    this.onSecret,
    this.onResult,
    this.onStep,
    this.onBack,
    this.onNext,
    super.key,
  });

  final LinkInstallVm vm;
  final VoidCallback onClose;
  final ValueChanged<InstallFrom>? onFrom;

  /// A category of the official list picked; null: all of them.
  final ValueChanged<String?>? onCategory;

  /// The words searched for in the official list; null: none.
  final ValueChanged<String?>? onQuery;
  final ValueChanged<String>? onItem;
  final ValueChanged<InstallMethod>? onMethod;
  final VoidCallback? onPickFile;

  /// The package URL or the Git repository's URL, and the Git ref, as they
  /// are typed (null: empty).
  final ValueChanged<String?>? onUrl;
  final ValueChanged<String?>? onRef;
  final ValueChanged<String>? onBroker;
  final ValueChanged<LinkRunMode>? onMode;
  final ValueChanged<String?>? onName;
  final ValueChanged<bool>? onAccept;

  /// The passphrase of the target step, as it is typed.
  final ValueChanged<String>? onSecret;
  final ValueChanged<InstallResultAction>? onResult;

  /// Back to a done step; null when no step can be picked.
  final ValueChanged<InstallStepKey>? onStep;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  /// The step's place in the rail, from 1.
  int get _at => vm.steps.indexOf(vm.step) + 1;

  /// How far the user got: the place of Where it runs, from 1.
  int get _run => vm.steps.indexOf(InstallStepKey.run) + 1;

  String get _modeWord => vm.mode.label;

  /// What was answered in [k], once it is done.
  String _answerOf(InstallStepKey k) => switch (k) {
    InstallStepKey.choose => vm.itemName ?? vm.sourceName ?? '',
    InstallStepKey.check =>
      vm.checkFailed ? S.current.failed : S.current.passed,
    InstallStepKey.run => '${vm.broker} · $_modeWord',
    InstallStepKey.result => '',
  };

  List<StepVm> get _rail => [
    for (final (i, k) in vm.steps.indexed)
      StepVm(
        title: k.title(official: vm.from == InstallFrom.official),
        sub: i + 1 == _at ? S.current.now : (i + 1 < _at ? _answerOf(k) : ''),
      ),
  ];

  List<AnswerVm> get _answers {
    final s = S.current;
    final reached = _at >= _run;
    return [
      AnswerVm(label: s.answerFrom, value: vm.from.title),
      AnswerVm(label: s.answerLink, value: vm.itemName ?? vm.sourceName ?? '—'),
      AnswerVm(label: s.answerBroker, value: reached ? vm.broker : '—'),
      AnswerVm(label: s.answerRuns, value: reached ? _modeWord : '—'),
      AnswerVm(
        label: s.answerName,
        value: (vm.name ?? '').isEmpty ? '—' : vm.name!,
      ),
      AnswerVm(
        label: s.answerRights,
        value: vm.offersAccept
            ? (vm.accepted
                  ? s.accepted
                  : (vm.from == InstallFrom.backup
                        ? s.backupRightsAsk
                        : s.toAccept))
            : s.noneAsked,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.ground0,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: WindowBar(
                vm: vm.window,
                padding: 16,
                child: Row(
                  spacing: 20,
                  children: [
                    const WyrmLogo(showStudio: false),
                    Text(
                      S.current.linksOn(vm.site),
                      style: TextStyle(
                        fontSize: FontSizes.lg,
                        color: c.text3,
                      ),
                    ),
                    Text('/', style: TextStyle(color: c.text4)),
                    Text(
                      S.current.addALink,
                      style: TextStyle(
                        fontSize: FontSizes.lg,
                        color: c.text1,
                      ),
                    ),
                    // The rest of the bar, the note at its right end: on
                    // a narrow window the note ends in an ellipsis instead
                    // of pushing the bar past the edge.
                    Expanded(
                      child: Align(
                        alignment: .centerRight,
                        child: Text(
                          S.current.needsConfigOnSys,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TextStyle(
                            fontSize: FontSizes.sm,
                            color: c.text3,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: AppIcon('ui_close', size: 18, color: c.text2),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= 1100;
                  final center = _Center(page: this);
                  if (!wide) {
                    return center;
                  }
                  return Row(
                    crossAxisAlignment: .stretch,
                    children: [
                      Container(
                        width: 220,
                        padding: Insets.wizardRail,
                        decoration: BoxDecoration(
                          color: c.ground1,
                          border: Border(right: BorderSide(color: c.line1)),
                        ),
                        child: Column(
                          crossAxisAlignment: .stretch,
                          children: [
                            Padding(
                              padding: Insets.wizardRailLabel,
                              child: SectionLabel(vm.from.rail),
                            ),
                            StepRail(
                              steps: _rail,
                              current: _at,
                              onStep: switch (onStep) {
                                final pick? when vm.canPickStep => (i) => pick(
                                  vm.steps[i - 1],
                                ),
                                _ => null,
                              },
                            ),
                            const Spacer(),
                            Divider(color: c.line1),
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Text(
                                S.current.installRailNote,
                                style: TextStyle(
                                  fontSize: FontSizes.sm,
                                  height: 1.5,
                                  color: c.text3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: center),
                      Container(
                        width: 280,
                        padding: Insets.wizardAnswers,
                        decoration: BoxDecoration(
                          color: c.ground1,
                          border: Border(left: BorderSide(color: c.line1)),
                        ),
                        child: SingleChildScrollView(
                          child: AnswerList(
                            title: S.current.yourAnswers,
                            note: S.current.yourAnswersNote,
                            answers: _answers,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Center extends StatelessWidget {
  const _Center({required this.page});

  final LinkInstallPage page;

  LinkInstallVm get vm => page.vm;

  bool get _official => vm.from == InstallFrom.official;
  bool get _backup => vm.from == InstallFrom.backup;

  String get _question => switch (vm.step) {
    InstallStepKey.choose => S.current.qChoose,
    InstallStepKey.check =>
      vm.checkFailed ? S.current.qCheckFailed : S.current.qCheckOk,
    InstallStepKey.run => S.current.qRun,
    InstallStepKey.result => switch (vm.result) {
      InstallResult.installing => S.current.qInstalling(vm.name ?? ''),
      InstallResult.failed => S.current.qFailed,
      InstallResult.done || null => S.current.qInstalled(vm.name ?? ''),
    },
  };

  String get _why => switch (vm.step) {
    InstallStepKey.choose =>
      _official
          ? S.current.whyChoose
          : (_backup ? S.current.whyBringBackup : S.current.whyBring),
    InstallStepKey.check => S.current.whyCheck,
    InstallStepKey.run =>
      _official
          ? S.current.whyRunOfficial
          : (_backup ? S.current.whyRunBackup : S.current.whyRunCustom),
    InstallStepKey.result => switch (vm.result) {
      InstallResult.installing => S.current.whyInstalling,
      InstallResult.failed => S.current.whyFailed,
      InstallResult.done || null => S.current.whyInstalled,
    },
  };

  /// What is wrong with the name, as said under it; null: nothing.
  String? get _nameError => switch (vm.nameError) {
    null => null,
    InstallNameError.rule => S.current.nameRule,
    InstallNameError.taken => S.current.nameTaken,
    InstallNameError.refused => vm.refusedSaid,
  };

  /// Why *Continue* is not offered, as said on its button.
  String? get _hold => switch (vm.hold) {
    null => null,
    InstallHold.pickOne => S.current.pickOne,
    InstallHold.bringOne => S.current.bringOne,
    InstallHold.checkFailed => S.current.checkFailed,
    InstallHold.nameIt => S.current.nameIt,
    InstallHold.nameProblem => _nameError ?? S.current.nameIt,
    InstallHold.acceptFirst => S.current.acceptFirst,
    InstallHold.needsConfig => vm.configReason?.text,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = page;
    final last = vm.step == InstallStepKey.result;
    final hold = last ? null : _hold;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: ListView(
            padding: Insets.wizardStep,
            children: [
              Text(
                S.current.stepOf(p._at, vm.steps.length),
                style: mono(color: c.text3),
              ),
              Gaps.caption,
              Text(
                _question,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Gaps.sm,
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Text(
                  _why,
                  style: TextStyle(
                    fontSize: FontSizes.lg,
                    height: 1.5,
                    color: c.text2,
                  ),
                ),
              ),
              Gaps.stepContent,
              ..._content(context, c),
            ],
          ),
        ),
        Container(
          padding: Insets.wizardFoot,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line1)),
          ),
          child: Row(
            children: [
              Button.secondary(label: S.current.back, onPressed: p.onBack),
              const Spacer(),
              if (!last)
                Button.primary(
                  label: vm.step == InstallStepKey.run
                      ? S.current.install
                      : S.current.continueLabel,
                  size: .commit,
                  disabledReason: hold,
                  onPressed: hold == null ? p.onNext : null,
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, AppColors c) => switch (vm.step) {
    InstallStepKey.choose => [
      _cards([
        for (final f in InstallFrom.values)
          ChoiceCardVm(
            id: f,
            title: f.title,
            detail: f.detail,
            selected: f == vm.from,
          ),
      ], page.onFrom),
      Gaps.stepGroup,
      if (_official) ..._catalog(c) else ..._bring(c),
    ],
    InstallStepKey.check => _check(c),
    InstallStepKey.run => _target(c),
    InstallStepKey.result => _result(),
  };

  List<Widget> _catalog(AppColors c) => [
    _CatalogFilter(
      categories: vm.categories,
      category: vm.category,
      query: vm.query,
      onCategory: page.onCategory,
      onQuery: page.onQuery,
    ),
    Gaps.md,
    LayoutBuilder(
      builder: (context, box) {
        final n = box.maxWidth > 840 ? 3 : (box.maxWidth > 540 ? 2 : 1);
        final w = (box.maxWidth - 12 * (n - 1)) / n;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in vm.cards)
              SizedBox(
                width: w,
                child: CatalogCard(
                  key: ValueKey('card:${card.id}'),
                  vm: card,
                  onTap: page.onItem,
                ),
              ),
          ],
        );
      },
    ),
    Gaps.closingNote,
    Text(
      S.current.catalogNote,
      style: TextStyle(fontSize: FontSizes.md, color: c.text3),
    ),
  ];

  List<Widget> _bring(AppColors c) {
    final method = vm.method;
    final hint = _backup ? InstallFrom.backupHint : method.fileHint;
    return [
      if (_backup)
        SegmentedTabs(
          tabs: const [
            TabItemVm(id: InstallFrom.backup, label: InstallFrom.backupTab),
          ],
          selected: InstallFrom.backup,
          onSelect: (_) {},
        )
      else
        SegmentedTabs(
          tabs: [
            for (final m in InstallMethod.values)
              TabItemVm(id: m, label: m.label),
          ],
          selected: method,
          onSelect: page.onMethod ?? (_) {},
        ),
      Gaps.md,
      if (hint != null)
        InkWell(
          onTap: page.onPickFile,
          borderRadius: Radii.card,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: c.ground2,
              border: .all(color: c.line2),
              borderRadius: Radii.card,
            ),
            child: Center(
              child: Column(
                mainAxisSize: .min,
                spacing: 8,
                children: [
                  AppIcon('ui_file', size: 24, color: c.text3),
                  Text(
                    vm.file ?? hint,
                    style: vm.file == null
                        ? TextStyle(fontSize: FontSizes.lg, color: c.text3)
                        : mono(size: 14, color: c.text1),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (!_backup && method.fields.isNotEmpty)
        ParamForm(
          fields: [
            for (final f in method.fields)
              ParamFieldVm(
                id: f.key,
                label: f.label,
                kind: .text,
                value: f == InstallText.ref ? vm.ref : vm.url,
                error: f == vm.refused ? vm.refusedSaid : null,
                hint: f.hint,
                onChanged: (v) =>
                    (f == InstallText.ref ? page.onRef : page.onUrl)?.call(
                      _textOf(v),
                    ),
              ),
          ],
          columns: 2,
        ),
    ];
  }

  List<Widget> _check(AppColors c) => [
    Text(
      S.current.checkedHere,
      style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
    ),
    Gaps.sectionTitle,
    CheckList(rows: [for (final c in vm.checks) c.row]),
    if (vm.manifest case final m?) ...[
      Gaps.stepGroup,
      SectionLabel(S.current.manifest),
      Gaps.sm,
      SizedBox(
        height: AppSizes.manifestView,
        child: LogView(lines: m.split('\n')),
      ),
    ],
  ];

  List<Widget> _target(AppColors c) {
    final name = vm.name ?? '';
    final rights = [
      for (final r in vm.rights)
        FactVm(label: r.kind, value: r.detail, mono: true),
      if (vm.rights.isEmpty && vm.result == InstallResult.failed)
        if (vm.message case final m?)
          FactVm(label: S.current.brokerSays, value: m),
    ];
    return [
      if (_official && vm.itemName != null) ...[
        ChoiceCard(
          vm: ChoiceCardVm(
            id: vm.itemName,
            title: vm.itemName!,
            detail: vm.itemBuiltIn
                ? S.current.builtInSummary
                : S.current.packageSummary,
          ),
        ),
        Gaps.stepGroup,
      ],
      Text(
        S.current.onWhichBroker,
        style: const TextStyle(fontSize: FontSizes.lg, fontWeight: .w600),
      ),
      Gaps.sectionTitle,
      _cards([
        for (final b in vm.brokers)
          ChoiceCardVm(
            id: b.site,
            title: b.site,
            badge: b.here ? S.current.thisBroker : S.current.downstream,
            detail: b.host,
            note: b.here
                ? S.current.studioSignedInHere
                : S.current.configAllowed,
            refused: b.refused?.text,
            selected: b.site == vm.broker,
            monoTitle: true,
            dot: true,
          ),
      ], page.onBroker),
      Gaps.stepGroup,
      Text(
        S.current.howItRunsThere,
        style: const TextStyle(fontSize: FontSizes.lg, fontWeight: .w600),
      ),
      Gaps.sectionTitle,
      _cards([
        for (final m in vm.modes)
          ChoiceCardVm(
            id: m,
            title: m.label,
            detail: m.note,
            selected: m == vm.mode,
            radio: true,
          ),
      ], page.onMode),
      Gaps.stepGroup,
      Align(
        alignment: .centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ParamField(
            vm: ParamFieldVm(
              id: InstallText.name.key,
              label: InstallText.name.label,
              kind: .text,
              value: vm.name,
              error: _nameError,
              onChanged: (v) => page.onName?.call(_textOf(v)),
            ),
          ),
        ),
      ),
      Gaps.caption,
      Text.rich(
        TextSpan(
          text: 'wy/${vm.broker}/downstream/',
          style: mono(size: 12, color: c.text4),
          children: [
            TextSpan(
              text: name,
              style: mono(size: 12, color: c.emberSoft),
            ),
          ],
        ),
      ),
      Text(
        S.current.nameRule,
        style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
      ),
      if (vm.replaces) ...[
        Gaps.caption,
        Text(
          S.current.backupReplaces(name),
          style: TextStyle(fontSize: FontSizes.sm, color: c.warn),
        ),
      ],
      if (_backup) ...[
        Gaps.stepGroup,
        Align(
          alignment: .centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ParamField(
              vm: ParamFieldVm(
                id: InstallText.passphrase.key,
                label: InstallText.passphrase.label,
                kind: .secret,
                description: S.current.backupPassphraseNote,
                onChanged: (v) => page.onSecret?.call(_textOf(v) ?? ''),
              ),
            ),
          ),
        ),
      ],
      if (vm.offersAccept) ...[
        Gaps.stepGroup,
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.warnTint,
            border: .all(color: c.warnLine),
            borderRadius: Radii.card,
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 10,
            children: [
              Text(
                S.current.rightsTitle,
                style: const TextStyle(
                  fontSize: FontSizes.lg,
                  fontWeight: .w600,
                ),
              ),
              if (rights.isNotEmpty) FactGrid(facts: rights),
              // Its own Material: a ListTile paints its ink on the
              // nearest one, which the tinted card would hide (a
              // Flutter assertion in debug builds).
              Material(
                type: .transparency,
                child: CheckboxListTile(
                  value: vm.accepted,
                  onChanged: (v) => page.onAccept?.call(v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: .leading,
                  activeColor: c.ember,
                  title: Text(
                    S.current.acceptRequestedRights,
                    style: const TextStyle(fontSize: FontSizes.lg),
                  ),
                ),
              ),
              Text(
                _backup ? S.current.backupRightsNote : S.current.rightsNote,
                style: TextStyle(fontSize: FontSizes.sm, color: c.text3),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _result() {
    final r = vm.result;
    final done = r == InstallResult.done;
    return [
      if (r == InstallResult.installing)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      if (r == InstallResult.done || r == InstallResult.failed) ...[
        Notice(
          vm: NoticeVm(
            tone: done ? Tone.good : Tone.bad,
            message: done
                ? S.current.installedOn(vm.name ?? '', vm.broker)
                : S.current.notInstalled,
            // A refusal with no words of the broker still says so.
            detail: vm.message ?? (done ? null : S.current.installNoWords),
          ),
        ),
        Gaps.md,
        Wrap(
          spacing: 10,
          children: [
            for (final a in InstallResultAction.of(r))
              Button.secondary(
                label: a.label,
                onPressed: () => page.onResult?.call(a),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _cards<T>(List<ChoiceCardVm<T>> cards, ValueChanged<T>? onTap) =>
      LayoutBuilder(
        builder: (context, box) {
          final n = cards.length.clamp(1, box.maxWidth > 800 ? 3 : 2);
          final w = (box.maxWidth - 12 * (n - 1)) / n;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards)
                SizedBox(
                  width: w,
                  child: ChoiceCard(
                    vm: card,
                    onTap: onTap == null ? null : () => onTap(card.id),
                  ),
                ),
            ],
          );
        },
      );
}

/// What a text field reports: its text, or none (a text field of
/// [ParamField] reports a `String` or null).
String? _textOf(Object? v) => switch (v) {
  final String s => s,
  _ => null,
};

/// The search field and the category chips of the official list: one
/// height (36), one vertical centre, on one line while the field keeps at
/// least [_minSearch] beside the chips; else the chips wrap under it.
class _CatalogFilter extends StatelessWidget {
  const _CatalogFilter({
    required this.categories,
    required this.category,
    required this.query,
    this.onCategory,
    this.onQuery,
  });

  /// The categories of the list; a chip *All* (null) comes first.
  final List<String> categories;
  final String? category;
  final String? query;
  final ValueChanged<String?>? onCategory;
  final ValueChanged<String?>? onQuery;

  /// The chips: *All*, then each category.
  List<String?> get _chips => [null, ...categories];

  static String _label(String? k) => k ?? S.current.catalogAll;

  static const _height = 36.0;
  static const _gap = 10.0;
  static const _minSearch = 280.0;
  static const _chipText = TextStyle(fontSize: FontSizes.md);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scaler = MediaQuery.textScalerOf(context);
    final font = DefaultTextStyle.of(context).style.merge(_chipText);
    final chips = [
      for (final k in _chips) _chip(c, k, selected: k == category),
    ];
    final search = _search(c);
    return LayoutBuilder(
      builder: (context, box) {
        final chipsWidth = [
          for (final k in _chips) _chipWidth(_label(k), font, scaler) + _gap,
        ].fold<double>(0, (a, b) => a + b);
        if (box.maxWidth - chipsWidth >= _minSearch) {
          return Row(
            spacing: _gap,
            children: [
              Expanded(child: search),
              ...chips,
            ],
          );
        }
        return Column(
          crossAxisAlignment: .stretch,
          spacing: _gap,
          children: [
            search,
            Wrap(spacing: _gap, runSpacing: _gap, children: chips),
          ],
        );
      },
    );
  }

  /// A chip's width: its word at 13 and 14 on each side.
  static double _chipWidth(String label, TextStyle font, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: font),
      textDirection: .ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = tp.width + 28 + 2;
    tp.dispose();
    return w;
  }

  Widget _search(AppColors c) => Container(
    key: const ValueKey('catalog-search'),
    height: _height,
    padding: Insets.control,
    decoration: BoxDecoration(
      color: c.ground3,
      border: .all(color: c.line2),
      borderRadius: Radii.segment,
    ),
    child: Row(
      spacing: 8,
      children: [
        AppIcon('ui_search', size: 14, color: c.text4),
        Expanded(
          child: TextFormField(
            initialValue: query,
            onChanged: (v) => onQuery?.call(v.isEmpty ? null : v),
            style: TextStyle(fontSize: FontSizes.md, color: c.text1),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: S.current.searchLinks,
              hintStyle: TextStyle(fontSize: FontSizes.md, color: c.text4),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _chip(AppColors c, String? k, {required bool selected}) => InkWell(
    key: ValueKey('category:${k ?? '*'}'),
    onTap: () => onCategory?.call(k),
    borderRadius: Radii.pill,
    child: Container(
      height: _height,
      padding: Insets.filterPill,
      decoration: BoxDecoration(
        color: selected ? c.ground4 : null,
        border: .all(color: selected ? c.line3 : c.line1),
        borderRadius: Radii.pill,
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          _label(k),
          maxLines: 1,
          style: TextStyle(
            fontSize: FontSizes.md,
            color: selected ? c.text1 : c.text3,
          ),
        ),
      ),
    ),
  );
}
