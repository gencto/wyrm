import 'package:flutter/material.dart';

import '../alerts/notice.dart';
import '../buttons/action_row.dart';
import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/fact_grid.dart';
import '../containers/section_label.dart';
import '../forms/param_form.dart';
import '../generated/assets.gen.dart';
import '../indicators/access_meter.dart';
import '../indicators/app_icon.dart';
import '../indicators/check_list.dart';
import '../indicators/progress_list.dart';
import '../indicators/quality_mark.dart';
import '../indicators/status_pill.dart';
import '../indicators/step_list.dart';
import '../indicators/tag_chip.dart';
import '../inputs/switch_row.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import '../trees/tree_row.dart';

/// The design system as one page (boards *Design system* and *Icons*): every
/// token and part of `ui`, drawn with the canvas's own sample data. Dev
/// builds only; the golden tests draw the same sections.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Design gallery')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: const Column(
            crossAxisAlignment: .stretch,
            spacing: 48,
            children: [
              GallerySection(
                number: '02',
                title: 'A cool graphite ground, one warm accent',
                child: ColorSwatches(),
              ),
              GallerySection(
                number: '03',
                title: 'Plex for reading, Mono for anything a machine reads',
                child: TypeScale(),
              ),
              GallerySection(
                number: '05',
                title: 'The same words the broker uses',
                child: StatusLanguage(),
              ),
              GallerySection(
                number: '06',
                title: 'The kit the screens are built from',
                child: ComponentKit(),
              ),
              GallerySection(
                number: 'Icons',
                title: '24 px grid, 1.8 px stroke, round caps',
                child: IconGrid(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A numbered section of the gallery.
class GallerySection extends StatelessWidget {
  const GallerySection({
    required this.number,
    required this.title,
    required this.child,
    super.key,
  });

  final String number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    spacing: 8,
    children: [
      Text(number, style: mono(color: context.colors.text4)),
      Text(
        title,
        style: const TextStyle(fontSize: 28, fontWeight: .w600),
      ),
      const SizedBox(height: 14),
      child,
    ],
  );
}

/// A panel of the gallery (radius 12, ground/1 on line/1).
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.colors.ground1,
      border: .all(color: context.colors.line1),
      borderRadius: Radii.panel,
    ),
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: .w600,
            color: context.colors.text2,
          ),
        ),
        child,
      ],
    ),
  );
}

/// Board *Design system* §02.
class ColorSwatches extends StatelessWidget {
  const ColorSwatches({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = <String, List<(String, Color, String)>>{
      'Ground': [
        ('ground/0', c.ground0, 'App background, workspace'),
        ('ground/1', c.ground1, 'Panels: tree, inspector'),
        ('ground/2', c.ground2, 'Cards, flow blocks'),
        ('ground/3', c.ground3, 'Inputs, hover, selected row'),
        ('ground/4', c.ground4, 'Chips, active rail item'),
        ('line/1', c.line1, 'Panel borders, dividers'),
        ('line/2', c.line2, 'Input borders'),
        ('line/3', c.line3, 'Secondary button border'),
      ],
      'Text': [
        ('text/1', c.text1, 'Primary text, values'),
        ('text/2', c.text2, 'Body in tables'),
        ('text/3', c.text3, 'Secondary, labels'),
        ('text/4', c.text4, 'Captions, keys'),
      ],
      'Accent': [
        ('ember', c.ember, 'Primary action, selection, staged'),
        ('ember/soft', c.emberSoft, 'Staged text, hover links'),
        ('ember/new', c.emberNew, 'New value in a diff'),
        ('ember/tint', c.emberTint, 'Selected tree row, OUT tag'),
      ],
      'State': [
        ('good', c.good, 'Good quality, connected, wires'),
        ('good/tint', c.goodTint, 'Good chip ground'),
        ('uncertain', c.warn, 'Uncertain, connecting, quarantine'),
        ('uncertain/tint', c.warnTint, 'Uncertain chip ground'),
        ('bad', c.bad, 'Bad, failed, invalid field'),
        ('bad/tint', c.badTint, 'Bad chip and notice ground'),
      ],
    };
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        for (final MapEntry(:key, :value) in groups.entries) ...[
          Text(key, style: const TextStyle(fontWeight: .w600)),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (name, color, use) in value)
                _Swatch(name: name, color: color, use: use),
            ],
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.color, required this.use});

  final String name;
  final Color color;
  final String use;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rgb = color.toARGB32() & 0xFFFFFF;
    final hex = '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return Container(
      width: 162,
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Container(height: 64, color: color),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(name, style: TextStyle(fontSize: 12, color: c.text1)),
                Text(hex, style: mono(size: 12, color: c.text4)),
                Text(use, style: TextStyle(fontSize: 12, color: c.text3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Board *Design system* §03.
class TypeScale extends StatelessWidget {
  const TypeScale({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final rows = <(String, Widget, String)>[
      (
        'display',
        Text('WYRM Studio', style: wordmark(size: 32)),
        'Unbounded 700 · 32',
      ),
      (
        'title/page',
        Text('Links on plant', style: t.headlineSmall),
        'Plex Sans 600 · 26/1.2',
      ),
      (
        'title/panel',
        Text('3 staged changes', style: t.titleLarge),
        'Plex Sans 600 · 20/1.3',
      ),
      (
        'body',
        Text(
          'Values update live. Nothing is written until you apply.',
          style: t.bodyLarge,
        ),
        'Plex Sans 400 · 14/1.5',
      ),
      (
        'label',
        Text('REGISTER', style: t.labelMedium?.copyWith(color: c.text1)),
        'Plex Sans 600 · 12 · caps +6%',
      ),
      (
        'mono/key',
        Text('wy/plant/downstream/modbus/tcp-boiler/plc1', style: mono()),
        'Plex Mono 400 · 13/1.5',
      ),
      (
        'mono/value',
        Text('64.1 °C', style: mono(size: 22)),
        'Plex Mono 400 · 22 · inspector value',
      ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.panel,
      ),
      child: Column(
        children: [
          for (final (name, sample, spec) in rows)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      name,
                      style: TextStyle(fontSize: 12, color: c.text4),
                    ),
                  ),
                  Expanded(child: sample),
                  Text(spec, style: TextStyle(fontSize: 12, color: c.text3)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Board *Design system* §05.
class StatusLanguage extends StatelessWidget {
  const StatusLanguage({super.key});

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: 16,
    runSpacing: 16,
    children: [
      SizedBox(
        width: 380,
        child: _Panel(
          title: 'Value quality',
          child: Column(
            crossAxisAlignment: .start,
            spacing: 14,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  StatusPill(
                    vm: StatusPillVm(label: 'good', tone: .good),
                  ),
                  StatusPill(
                    vm: StatusPillVm(
                      label: 'uncertain',
                      tone: .warn,
                      mark: .ring,
                    ),
                  ),
                  StatusPill(
                    vm: StatusPillVm(label: 'bad', tone: .bad, mark: .cross),
                  ),
                  StatusPill(
                    vm: StatusPillVm(
                      label: 'stale',
                      tone: .neutral,
                      mark: .dashed,
                    ),
                  ),
                ],
              ),
              SectionLabel('Edit state'),
              Wrap(
                spacing: 16,
                children: [
                  QualityMark(
                    vm: QualityMarkVm(label: 'staged · was 1 s', tone: .ember),
                  ),
                  QualityMark(
                    vm: QualityMarkVm(
                      label: 'not applied',
                      tone: .neutral,
                      mark: .ring,
                    ),
                  ),
                  QualityMark(
                    vm: QualityMarkVm(
                      label: 'read back',
                      tone: .good,
                      mark: .check,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      SizedBox(
        width: 380,
        child: _Panel(
          title: 'Connection, device and point state',
          child: Column(
            crossAxisAlignment: .start,
            spacing: 14,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 10,
                children: [
                  QualityMark(
                    vm: QualityMarkVm(
                      label: 'New',
                      tone: .neutral,
                      mark: .ring,
                    ),
                  ),
                  QualityMark(
                    vm: QualityMarkVm(
                      label: 'Connecting',
                      tone: .warn,
                      mark: .ring,
                    ),
                  ),
                  QualityMark(
                    vm: QualityMarkVm(label: 'Connected', tone: .good),
                  ),
                  QualityMark(
                    vm: QualityMarkVm(label: 'Stopped', tone: .neutral),
                  ),
                  QualityMark(
                    vm: QualityMarkVm(label: 'Failed', tone: .bad),
                  ),
                  QualityMark(
                    vm: QualityMarkVm(
                      label: 'StoppedByParent',
                      tone: .neutral,
                      mark: .ring,
                    ),
                  ),
                ],
              ),
              SectionLabel('Run mode'),
              Wrap(
                spacing: 8,
                children: [
                  TagChip(vm: TagChipVm(label: 'Embedded')),
                  TagChip(vm: TagChipVm(label: 'WASM')),
                  TagChip(vm: TagChipVm(label: 'Process')),
                  TagChip(vm: TagChipVm(label: 'External')),
                ],
              ),
            ],
          ),
        ),
      ),
      SizedBox(
        width: 380,
        child: _Panel(
          title: 'Access level',
          child: AccessMeter(level: 'write'),
        ),
      ),
    ],
  );
}

/// Board *Design system* §06.
class ComponentKit extends StatelessWidget {
  const ComponentKit({super.key});

  @override
  Widget build(BuildContext context) {
    void none(Object? _) {}
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: 380,
          child: _Panel(
            title: 'Buttons',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Button.primary(label: 'Primary', onPressed: () {}),
                Button.secondary(label: 'Secondary', onPressed: () {}),
                Button.quiet(label: 'Quiet', onPressed: () {}),
                Button.danger(label: 'Remove', onPressed: () {}),
                Button.secondary(label: '', icon: 'ui_add', onPressed: () {}),
                const Button.secondary(
                  label: 'Stop',
                  onPressed: null,
                  disabledReason: 'done on the device',
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 380,
          child: _Panel(
            title: 'Fields',
            child: ParamForm(
              columns: 2,
              fields: [
                ParamFieldVm(
                  id: 'text',
                  label: 'Text',
                  kind: .text,
                  value: 'Return temp',
                  onChanged: none,
                ),
                ParamFieldVm(
                  id: 'num',
                  label: 'Number with unit',
                  kind: .number,
                  value: 1500,
                  unit: 'ms',
                  onChanged: none,
                ),
                ParamFieldVm(
                  id: 'choice',
                  label: 'Choice',
                  kind: .choice,
                  value: 'float32',
                  choices: const ['float32', 'uint16', 'bool'],
                  onChanged: none,
                ),
                ParamFieldVm(
                  id: 'addr',
                  label: 'Address',
                  kind: .number,
                  error: 'out of range',
                  onChanged: none,
                ),
                ParamFieldVm(
                  id: 'secret',
                  label: 'Secret',
                  kind: .secret,
                  description: 'sealed, never shown again',
                  onChanged: none,
                ),
                ParamFieldVm(
                  id: 'zip',
                  label: 'Package',
                  kind: .file,
                  hint: 'Choose a .zip',
                  onChanged: none,
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 380,
          child: _Panel(
            title: 'Toggles and choices',
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 12,
              children: [
                SwitchRow(
                  title: 'Hold unknown connections',
                  description: 'New devices wait in Quarantine',
                  keyName: 'sys/enable_quarantine',
                  vm: FieldVm(value: true, onChanged: none),
                ),
                SwitchRow(
                  title: 'Allow all links',
                  keyName: 'sys/allow_all_links',
                  vm: FieldVm(value: false, onChanged: none),
                ),
                SegmentedTabs(
                  tabs: const [
                    TabItemVm(id: 'points', label: 'Points', count: '9'),
                    TabItemVm(id: 'params', label: 'Parameters'),
                    TabItemVm(id: 'history', label: 'History'),
                  ],
                  selected: 'points',
                  onSelect: none,
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 380,
          child: _Panel(
            title: 'Tree rows',
            child: Column(
              spacing: 6,
              children: [
                const TreeRow(
                  vm: TreeRowVm(
                    id: 'a',
                    name: 'modbus',
                    depth: 0,
                    icon: 'node_link',
                    hasChildren: true,
                    expanded: true,
                    chip: 'Process',
                    dot: .good,
                  ),
                ),
                const TreeRow(
                  vm: TreeRowVm(
                    id: 'b',
                    name: 'plc1',
                    depth: 1,
                    icon: 'node_device',
                    hasChildren: true,
                    selected: true,
                    meta: '9',
                  ),
                ),
                const TreeRow(
                  vm: TreeRowVm(
                    id: 'c',
                    name: 'plc2',
                    depth: 1,
                    icon: 'node_device',
                    hasChildren: true,
                    staged: true,
                    meta: '14',
                  ),
                ),
                TreeRow(
                  vm: const TreeRowVm(
                    id: 'd',
                    name: 'boiler-guard',
                    depth: 0,
                    icon: 'node_flow',
                    meta: 'draft',
                  ),
                  onTap: none,
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 380,
          child: _Panel(
            title: 'Actions and facts',
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 12,
              children: [
                const FactGrid(
                  facts: [
                    FactVm(label: 'Driver', value: 'modbus', mono: true),
                    FactVm(label: 'Mode', value: 'Process'),
                    FactVm(label: 'Version', value: '0.1.0', mono: true),
                  ],
                ),
                ActionRow(
                  vm: const ActionRowVm(
                    id: 'start',
                    title: 'Start',
                    icon: 'action_play',
                    description: 'Run the link again',
                    code: 'start',
                  ),
                  onTap: none,
                ),
                ActionRow(
                  vm: const ActionRowVm(
                    id: 'remove',
                    title: 'Remove',
                    icon: 'action_trash',
                    description: 'Its id is retired',
                    code: 'remove',
                    tone: .bad,
                  ),
                  onTap: none,
                ),
                const ActionRow(
                  vm: ActionRowVm(
                    id: 'upgrade',
                    title: 'Upgrade',
                    icon: 'action_up',
                    code: 'install_repo',
                    disabledReason: 'needs config on sys',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(
          width: 380,
          child: _Panel(
            title: 'Change card and notices',
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 12,
              children: [
                Notice(
                  vm: NoticeVm(
                    message:
                        'bacnet stopped: fuel limit reached on start. The '
                        'component was stopped; the broker keeps running.',
                    tone: .bad,
                  ),
                ),
                Notice(
                  vm: NoticeVm(
                    message: '2 changes applied and read back.',
                    detail: 'sys/audit/modbus',
                    tone: .good,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(
          width: 380,
          child: _Panel(
            title: 'Steps, progress and checks',
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 16,
              children: [
                StepList(
                  steps: ['Choose', 'Where it runs', 'Install'],
                  current: 2,
                ),
                ProgressList(
                  rows: [
                    ProgressRowVm(label: 'Download', state: .done),
                    ProgressRowVm(
                      label: 'Check',
                      state: .now,
                      detail: 'wyrm-link.json',
                    ),
                    ProgressRowVm(label: 'Start', state: .waiting),
                  ],
                ),
                CheckList(
                  rows: [
                    CheckRowVm(
                      title: 'Manifest',
                      result: .ok,
                      detail: 'wyrm_link 1',
                    ),
                    CheckRowVm(
                      title: 'Binary for this host',
                      result: .failed,
                      detail: 'no linux-aarch64 asset',
                    ),
                    CheckRowVm(title: 'Signature', result: .skipped),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Board *Icons*: every icon of `ui/assets/svg/icons` with its name.
class IconGrid extends StatelessWidget {
  const IconGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final names = [
      for (final i in Assets.svg.icons.values)
        i.path.split('/').last.replaceAll('.svg', ''),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final n in names)
          Container(
            width: 132,
            height: 84,
            decoration: BoxDecoration(
              color: c.ground1,
              border: .all(color: c.line1),
              borderRadius: Radii.card,
            ),
            child: Column(
              mainAxisAlignment: .center,
              spacing: 10,
              children: [
                AppIcon(n, size: 24, color: c.text1),
                Text(n, style: mono(size: 11, color: c.text3)),
              ],
            ),
          ),
      ],
    );
  }
}
