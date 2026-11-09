import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

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
import '../models/value_changed.dart';
import '../overlays/log_view.dart';
import '../shell/window_bar.dart';
import '../shell/wyrm_logo.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What the Choose step lists.
final class CatalogPartVm extends Equatable {
  const CatalogPartVm({
    required this.categories,
    required this.category,
    required this.cards,
    required this.note,
    required this.query,
    this.searchHint = '',
  });

  final String searchHint;
  final List<String> categories;
  final String category;
  final List<CatalogCardVm> cards;
  final String note;
  final FieldVm<String?> query;

  @override
  List<Object?> get props => [
    categories,
    category,
    cards,
    note,
    query,
    searchHint,
  ];
}

/// What the Bring step of a custom package asks.
final class BringPartVm extends Equatable {
  const BringPartVm({
    required this.methods,
    required this.method,
    required this.fields,
    this.file,
    this.fileHint,
  });

  final List<TabItemVm> methods;
  final String method;

  /// URL, Git URL and ref.
  final List<ParamFieldVm> fields;

  /// The picked file's name (zip, wasm).
  final String? file;

  /// `Choose a .zip` when a file is asked.
  final String? fileHint;

  @override
  List<Object?> get props => [methods, method, fields, file, fileHint];
}

/// What the Where-it-runs step asks.
final class TargetPartVm extends Equatable {
  const TargetPartVm({
    required this.brokers,
    required this.modes,
    required this.name,
    required this.keyPreview,
    required this.nameRule,
    this.summary,
    this.rights = const [],
    this.accept,
    this.rightsTitle,
    this.rightsNote,
  });

  final ChoiceCardVm? summary;
  final List<ChoiceCardVm> brokers;
  final List<ChoiceCardVm> modes;
  final FieldVm<String?> name;

  /// `wy/plant/downstream/` and the name.
  final (String, String) keyPreview;
  final String nameRule;
  final List<FactVm> rights;
  final FieldVm<bool>? accept;
  final String? rightsTitle;
  final String? rightsNote;

  @override
  List<Object?> get props => [
    summary,
    brokers,
    modes,
    name,
    keyPreview,
    nameRule,
    rights,
    accept,
    rightsTitle,
    rightsNote,
  ];
}

/// The words of the frame, localized by the connector.
final class InstallLabels extends Equatable {
  const InstallLabels({
    required this.crumb,
    required this.title,
    required this.needs,
    required this.railLabel,
    required this.railNote,
    required this.stepOf,
    required this.question,
    required this.why,
    required this.answersTitle,
    required this.answersNote,
    required this.back,
    required this.next,
    required this.onBroker,
    required this.howItRuns,
    required this.linkName,
    required this.accept,
    required this.checkedHere,
    required this.manifest,
  });

  final String crumb;
  final String title;
  final String needs;
  final String railLabel;
  final String railNote;
  final String stepOf;
  final String question;
  final String why;
  final String answersTitle;
  final String answersNote;
  final String back;
  final String next;
  final String onBroker;
  final String howItRuns;
  final String linkName;
  final String accept;
  final String checkedHere;
  final String manifest;

  @override
  List<Object?> get props => [
    crumb,
    title,
    needs,
    railLabel,
    railNote,
    stepOf,
    question,
    why,
    answersTitle,
    answersNote,
    back,
    next,
    onBroker,
    howItRuns,
    linkName,
    accept,
    checkedHere,
    manifest,
  ];
}

/// Board *Add a link* (rows Official and Custom): steps on the left, the
/// step in the middle, the answers on the right, Back and Continue below.
class LinkInstallPage extends StatelessWidget {
  const LinkInstallPage({
    required this.labels,
    required this.steps,
    required this.step,
    required this.answers,
    required this.onClose,
    this.sources = const [],
    this.onSource,
    this.catalog,
    this.onCategory,
    this.onItem,
    this.bring,
    this.onMethod,
    this.onPickFile,
    this.checks,
    this.manifest,
    this.target,
    this.onBroker,
    this.onMode,
    this.result,
    this.resultActions = const [],
    this.onResultAction,
    this.installing = false,
    this.onStep,
    this.onBack,
    this.onNext,
    this.nextReason,
    this.nextIsInstall = false,
    this.window = const WindowBarVm(),
    super.key,
  });

  final InstallLabels labels;
  final List<StepVm> steps;
  final int step;
  final List<(String, String)> answers;
  final VoidCallback onClose;

  final List<ChoiceCardVm> sources;
  final ValueChanged<String>? onSource;
  final CatalogPartVm? catalog;
  final ValueChanged<String>? onCategory;
  final ValueChanged<String>? onItem;
  final BringPartVm? bring;
  final ValueChanged<String>? onMethod;
  final VoidCallback? onPickFile;
  final List<CheckRowVm>? checks;
  final String? manifest;
  final TargetPartVm? target;
  final ValueChanged<String>? onBroker;
  final ValueChanged<String>? onMode;
  final NoticeVm? result;
  final List<(String, String)> resultActions;
  final ValueChanged<String>? onResultAction;
  final bool installing;
  final ValueChanged<int>? onStep;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String? nextReason;
  final bool nextIsInstall;

  /// The frameless window's side of the top bar (docs/studio.md §7.1).
  final WindowBarVm window;

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
                vm: window,
                padding: 16,
                child: Row(
                  spacing: 20,
                  children: [
                    const WyrmLogo(showStudio: false),
                    Text(
                      labels.crumb,
                      style: TextStyle(fontSize: 14, color: c.text3),
                    ),
                    Text('/', style: TextStyle(color: c.text4)),
                    Text(
                      labels.title,
                      style: TextStyle(fontSize: 14, color: c.text1),
                    ),
                    const Spacer(),
                    Text(
                      labels.needs,
                      style: TextStyle(fontSize: 12, color: c.text3),
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
                        padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
                        decoration: BoxDecoration(
                          color: c.ground1,
                          border: Border(right: BorderSide(color: c.line1)),
                        ),
                        child: Column(
                          crossAxisAlignment: .stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 8,
                                bottom: 12,
                              ),
                              child: SectionLabel(labels.railLabel),
                            ),
                            StepRail(
                              steps: steps,
                              current: step,
                              onStep: onStep,
                            ),
                            const Spacer(),
                            Divider(color: c.line1),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                labels.railNote,
                                style: TextStyle(
                                  fontSize: 12,
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
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: c.ground1,
                          border: Border(left: BorderSide(color: c.line1)),
                        ),
                        child: SingleChildScrollView(
                          child: AnswerList(
                            title: labels.answersTitle,
                            note: labels.answersNote,
                            answers: answers,
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = page;
    final l = p.labels;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(30, 28, 30, 30),
            children: [
              Text(l.stepOf, style: mono(color: c.text3)),
              const SizedBox(height: 6),
              Text(
                l.question,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Text(
                  l.why,
                  style: TextStyle(fontSize: 14, height: 1.5, color: c.text2),
                ),
              ),
              const SizedBox(height: 20),
              ..._content(context, c),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line1)),
          ),
          child: Row(
            children: [
              Button.secondary(label: l.back, onPressed: p.onBack),
              const Spacer(),
              if (p.onNext != null || p.nextReason != null)
                Button.primary(
                  label: l.next,
                  size: .commit,
                  disabledReason: p.nextReason,
                  onPressed: p.nextReason == null ? p.onNext : null,
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, AppColors c) {
    final p = page;
    final l = p.labels;
    return [
      if (p.sources.isNotEmpty) ...[
        _cards(p.sources, p.onSource),
        const SizedBox(height: 18),
      ],
      if (p.catalog case final cat?) ...[
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: ParamField(
                vm: ParamFieldVm(
                  id: 'query',
                  label: '',
                  kind: .text,
                  value: cat.query.value,
                  hint: cat.searchHint,
                  onChanged: (v) => cat.query.onChanged(v as String?),
                ),
              ),
            ),
            for (final k in cat.categories)
              InkWell(
                onTap: () => p.onCategory?.call(k),
                borderRadius: Radii.pill,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: k == cat.category ? c.ground4 : null,
                    border: .all(
                      color: k == cat.category ? c.line3 : c.line1,
                    ),
                    borderRadius: Radii.pill,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      k,
                      style: TextStyle(
                        fontSize: 13,
                        color: k == cat.category ? c.text1 : c.text3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final n = box.maxWidth > 840 ? 3 : (box.maxWidth > 540 ? 2 : 1);
            final w = (box.maxWidth - 12 * (n - 1)) / n;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cat.cards)
                  SizedBox(
                    width: w,
                    child: CatalogCard(vm: card, onTap: p.onItem),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text(cat.note, style: TextStyle(fontSize: 13, color: c.text3)),
      ],
      if (p.bring case final b?) ...[
        SegmentedTabs(
          tabs: b.methods,
          selected: b.method,
          onSelect: p.onMethod ?? (_) {},
        ),
        const SizedBox(height: 16),
        if (b.fileHint != null)
          InkWell(
            onTap: p.onPickFile,
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
                      b.file ?? b.fileHint!,
                      style: b.file == null
                          ? TextStyle(fontSize: 14, color: c.text3)
                          : mono(size: 14, color: c.text1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (b.fields.isNotEmpty) ParamForm(fields: b.fields, columns: 2),
      ],
      if (p.checks case final ch?) ...[
        Text(l.checkedHere, style: TextStyle(fontSize: 12, color: c.text4)),
        const SizedBox(height: 10),
        CheckList(rows: ch),
        if (p.manifest case final m?) ...[
          const SizedBox(height: 18),
          SectionLabel(l.manifest),
          const SizedBox(height: 8),
          SizedBox(height: 220, child: LogView(lines: m.split('\n'))),
        ],
      ],
      if (p.target case final t?) ...[
        if (t.summary case final s?) ...[
          ChoiceCard(vm: s),
          const SizedBox(height: 18),
        ],
        Text(
          l.onBroker,
          style: const TextStyle(fontSize: 14, fontWeight: .w600),
        ),
        const SizedBox(height: 10),
        _cards(t.brokers, p.onBroker),
        const SizedBox(height: 18),
        Text(
          l.howItRuns,
          style: const TextStyle(fontSize: 14, fontWeight: .w600),
        ),
        const SizedBox(height: 10),
        _cards(t.modes, p.onMode),
        const SizedBox(height: 18),
        Align(
          alignment: .centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ParamField(
              vm: ParamFieldVm(
                id: 'name',
                label: l.linkName,
                kind: .text,
                value: t.name.value,
                error: t.name.error,
                onChanged: (v) => t.name.onChanged(v as String?),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text: t.keyPreview.$1,
            style: mono(size: 12, color: c.text4),
            children: [
              TextSpan(
                text: t.keyPreview.$2,
                style: mono(size: 12, color: c.emberSoft),
              ),
            ],
          ),
        ),
        Text(t.nameRule, style: TextStyle(fontSize: 12, color: c.text4)),
        if (t.accept case final a?) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
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
                  t.rightsTitle ?? '',
                  style: const TextStyle(fontSize: 14, fontWeight: .w600),
                ),
                if (t.rights.isNotEmpty) FactGrid(facts: t.rights),
                CheckboxListTile(
                  value: a.value,
                  onChanged: (v) => a.onChanged(v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: .leading,
                  activeColor: c.ember,
                  title: Text(l.accept, style: const TextStyle(fontSize: 14)),
                ),
                if (t.rightsNote case final n?)
                  Text(n, style: TextStyle(fontSize: 12, color: c.text3)),
              ],
            ),
          ),
        ],
      ],
      if (p.installing && p.result == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      if (p.result case final r?) ...[
        Notice(vm: r),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          children: [
            for (final (id, label) in p.resultActions)
              Button.secondary(
                label: label,
                onPressed: () => p.onResultAction?.call(id),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _cards(List<ChoiceCardVm> cards, ValueChanged<String>? onTap) =>
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
                  child: ChoiceCard(vm: card, onTap: onTap),
                ),
            ],
          );
        },
      );
}
