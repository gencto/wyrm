import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What the flow canvas can be told to do, by a key, by the pointer or
/// from its context menu (studio/docs/design/specs/flow-editor.md §14).
enum FlowCommand {
  selectAll,
  marquee,
  addToSelection,
  moveSelection,
  nudgeLeft,
  nudgeRight,
  nudgeUp,
  nudgeDown,
  escape,
  copy,
  cut,
  paste,
  duplicate,
  delete,
  undo,
  redo,
  unbind,
  pan,
  zoom,
  zoomIn,
  zoomOut,
  zoomReset,
  zoomFit,
  viewValue,
  searchPalette,
  deploy,
  help,

  /// Only in the context menu.
  fields,
  unpin,
  createCustomBlock,
  editCustomBlock,
}

/// What the pointer does in a [FlowGesture].
enum FlowPointer {
  click,
  doubleClick,
  drag,
  dragEmpty,
  dragHeader,
  middleDrag,
  scroll,
  wheel,
  pinch,
}

/// One key that runs a command: [key] (or one of [also], the same key
/// elsewhere on the keyboard) with exactly these modifiers. [primary] is
/// ⌘ on macOS and Ctrl elsewhere. A null [shift] takes the key with or
/// without Shift (`?` is Shift+/ on most layouts, `+` is Shift+=).
final class FlowKey {
  const FlowKey(
    this.key,
    this.label, {
    this.also = const [],
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.listed = true,
  });

  final LogicalKeyboardKey key;
  final List<LogicalKeyboardKey> also;

  /// What the card prints for the key itself (`Z`, `Delete`, `←`).
  final String label;
  final bool primary;
  final bool? shift;
  final bool alt;

  /// Whether the card shows it (a second spelling of the same key is not).
  final bool listed;

  bool matches(
    LogicalKeyboardKey pressed, {
    required bool primary,
    required bool shift,
    required bool alt,
  }) =>
      (pressed == key || also.contains(pressed)) &&
      primary == this.primary &&
      alt == this.alt &&
      (this.shift == null || this.shift == shift);
}

/// One thing the pointer does for a command: [pointer], with the keys held.
final class FlowGesture {
  const FlowGesture(
    this.pointer, {
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.space = false,
  });

  final FlowPointer pointer;
  final bool primary;
  final bool shift;
  final bool alt;
  final bool space;
}

/// The groups of the shortcut card.
enum FlowShortcutGroup { select, edit, view }

/// One row of the shortcut table: a command and every way to give it.
final class FlowShortcut {
  const FlowShortcut(
    this.command,
    this.group, {
    this.keys = const [],
    this.gestures = const [],
  });

  final FlowCommand command;
  final FlowShortcutGroup group;
  final List<FlowKey> keys;
  final List<FlowGesture> gestures;
}

/// The shortcuts of the flow canvas: THE table. The canvas finds the
/// command of a key here ([flowCommandOf]) and reads the modifiers of its
/// pointer gestures here ([flowGestureHeld]); the card ([ShortcutCard]) and the
/// hints of the context menu ([flowHintOf]) print the same rows. A shortcut
/// that is not in this table does not exist.
const flowShortcuts = <FlowShortcut>[
  // ----- selection -----
  FlowShortcut(
    .selectAll,
    .select,
    keys: [FlowKey(LogicalKeyboardKey.keyA, 'A', primary: true)],
  ),
  FlowShortcut(
    .marquee,
    .select,
    gestures: [FlowGesture(.dragEmpty)],
  ),
  FlowShortcut(
    .addToSelection,
    .select,
    gestures: [
      FlowGesture(.click, shift: true),
      FlowGesture(.click, primary: true),
      FlowGesture(.dragEmpty, shift: true),
    ],
  ),
  FlowShortcut(
    .moveSelection,
    .select,
    gestures: [FlowGesture(.dragHeader)],
  ),
  FlowShortcut(
    .nudgeLeft,
    .select,
    keys: [FlowKey(LogicalKeyboardKey.arrowLeft, '←', shift: null)],
  ),
  FlowShortcut(
    .nudgeRight,
    .select,
    keys: [FlowKey(LogicalKeyboardKey.arrowRight, '→', shift: null)],
  ),
  FlowShortcut(
    .nudgeUp,
    .select,
    keys: [FlowKey(LogicalKeyboardKey.arrowUp, '↑', shift: null)],
  ),
  FlowShortcut(
    .nudgeDown,
    .select,
    keys: [FlowKey(LogicalKeyboardKey.arrowDown, '↓', shift: null)],
  ),
  FlowShortcut(
    .escape,
    .select,
    keys: [FlowKey(LogicalKeyboardKey.escape, 'Esc')],
  ),
  // ----- editing -----
  FlowShortcut(
    .copy,
    .edit,
    keys: [FlowKey(LogicalKeyboardKey.keyC, 'C', primary: true)],
  ),
  FlowShortcut(
    .cut,
    .edit,
    keys: [FlowKey(LogicalKeyboardKey.keyX, 'X', primary: true)],
  ),
  FlowShortcut(
    .paste,
    .edit,
    keys: [FlowKey(LogicalKeyboardKey.keyV, 'V', primary: true)],
  ),
  FlowShortcut(
    .duplicate,
    .edit,
    keys: [FlowKey(LogicalKeyboardKey.keyD, 'D', primary: true)],
  ),
  FlowShortcut(
    .delete,
    .edit,
    keys: [
      FlowKey(LogicalKeyboardKey.delete, 'Delete'),
      FlowKey(LogicalKeyboardKey.backspace, 'Backspace'),
    ],
  ),
  FlowShortcut(
    .undo,
    .edit,
    keys: [FlowKey(LogicalKeyboardKey.keyZ, 'Z', primary: true)],
  ),
  FlowShortcut(
    .redo,
    .edit,
    keys: [
      FlowKey(LogicalKeyboardKey.keyZ, 'Z', primary: true, shift: true),
      FlowKey(LogicalKeyboardKey.keyY, 'Y', primary: true),
    ],
  ),
  FlowShortcut(
    .unbind,
    .edit,
    gestures: [FlowGesture(.click, alt: true), FlowGesture(.doubleClick)],
  ),
  // ----- view -----
  FlowShortcut(
    .pan,
    .view,
    gestures: [
      FlowGesture(.drag, space: true),
      FlowGesture(.middleDrag),
      FlowGesture(.scroll),
    ],
  ),
  FlowShortcut(
    .zoom,
    .view,
    gestures: [FlowGesture(.wheel, primary: true), FlowGesture(.pinch)],
  ),
  FlowShortcut(
    .zoomIn,
    .view,
    keys: [
      FlowKey(
        LogicalKeyboardKey.equal,
        '+',
        also: [LogicalKeyboardKey.add, LogicalKeyboardKey.numpadAdd],
        primary: true,
        shift: null,
      ),
    ],
  ),
  FlowShortcut(
    .zoomOut,
    .view,
    keys: [
      FlowKey(
        LogicalKeyboardKey.minus,
        '−',
        also: [LogicalKeyboardKey.numpadSubtract],
        primary: true,
        shift: null,
      ),
    ],
  ),
  FlowShortcut(
    .zoomReset,
    .view,
    keys: [
      FlowKey(
        LogicalKeyboardKey.digit0,
        '0',
        also: [LogicalKeyboardKey.numpad0],
        primary: true,
      ),
      FlowKey(LogicalKeyboardKey.digit1, '1'),
    ],
  ),
  FlowShortcut(
    .zoomFit,
    .view,
    keys: [
      FlowKey(LogicalKeyboardKey.digit1, '1', shift: true),
      FlowKey(
        LogicalKeyboardKey.exclamation,
        '!',
        shift: null,
        listed: false,
      ),
    ],
  ),
  FlowShortcut(
    .viewValue,
    .view,
    keys: [FlowKey(LogicalKeyboardKey.keyV, 'V')],
  ),
  FlowShortcut(
    .searchPalette,
    .view,
    keys: [
      FlowKey(LogicalKeyboardKey.slash, '/'),
      FlowKey(LogicalKeyboardKey.keyK, 'K', primary: true),
    ],
  ),
  FlowShortcut(
    .deploy,
    .view,
    keys: [
      FlowKey(
        LogicalKeyboardKey.enter,
        'Enter',
        also: [LogicalKeyboardKey.numpadEnter],
        primary: true,
      ),
    ],
  ),
  FlowShortcut(
    .help,
    .view,
    keys: [
      FlowKey(LogicalKeyboardKey.question, '?', shift: null),
      FlowKey(LogicalKeyboardKey.slash, '/', shift: true, listed: false),
    ],
  ),
];

/// Whether this machine's primary modifier is ⌘ (macOS) rather than Ctrl.
bool get flowOnMac =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Whether the primary modifier is held: ⌘ on macOS, Ctrl elsewhere.
bool flowPrimaryHeld([HardwareKeyboard? keyboard]) {
  final k = keyboard ?? HardwareKeyboard.instance;
  return flowOnMac ? k.isMetaPressed : k.isControlPressed;
}

/// The command [pressed] gives with the modifiers held now; null: none.
FlowCommand? flowCommandOf(
  LogicalKeyboardKey pressed, {
  HardwareKeyboard? keyboard,
}) {
  final k = keyboard ?? HardwareKeyboard.instance;
  final primary = flowPrimaryHeld(k);
  // The other of ⌘ / Ctrl held is another chord: not ours.
  if (flowOnMac ? k.isControlPressed : k.isMetaPressed) {
    return null;
  }
  for (final s in flowShortcuts) {
    for (final key in s.keys) {
      if (key.matches(
        pressed,
        primary: primary,
        shift: k.isShiftPressed,
        alt: k.isAltPressed,
      )) {
        return s.command;
      }
    }
  }
  return null;
}

/// The row of [command].
FlowShortcut? flowShortcutOf(FlowCommand command) {
  for (final s in flowShortcuts) {
    if (s.command == command) {
      return s;
    }
  }
  return null;
}

/// Whether the keys held now are those of a gesture of [command] done
/// with [pointer] (`unbind` + `click`: Alt held, nothing else).
bool flowGestureHeld(
  FlowCommand command,
  FlowPointer pointer, {
  HardwareKeyboard? keyboard,
  bool space = false,
}) {
  final k = keyboard ?? HardwareKeyboard.instance;
  final primary = flowPrimaryHeld(k);
  return flowShortcutOf(command)?.gestures.any(
        (g) =>
            g.pointer == pointer &&
            g.primary == primary &&
            g.shift == k.isShiftPressed &&
            g.alt == k.isAltPressed &&
            g.space == space,
      ) ??
      false;
}

/// The keys of [key] as the card's chips: `⌘ ⇧ Z` on macOS, `Ctrl Shift
/// Z` elsewhere. IBM Plex has no ⌘ ⌥ ⇧ and no arrows: [KeyGlyph] draws
/// those as icons.
List<String> flowKeyChips(FlowKey key, {bool? mac}) => [
  ..._modifiers(
    mac ?? flowOnMac,
    primary: key.primary,
    shift: key.shift ?? false,
    alt: key.alt,
  ),
  key.label,
];

List<String> _modifiers(
  bool mac, {
  required bool primary,
  required bool shift,
  required bool alt,
}) => [
  if (primary)
    if (mac) '⌘' else 'Ctrl',
  if (alt)
    if (mac) '⌥' else 'Alt',
  if (shift)
    if (mac) '⇧' else 'Shift',
];

/// The first key of [command] in one text (`⌘C`, `Ctrl+C`): the hint on
/// the right of a menu item; empty when it has none.
String flowHintOf(FlowCommand command, {bool? mac}) {
  final m = mac ?? flowOnMac;
  final key = flowShortcutOf(command)?.keys.where((k) => k.listed).firstOrNull;
  return key == null ? '' : flowKeyChips(key, mac: m).join(m ? '' : '+');
}

/// The gesture [g] as chips: the keys held, then what the pointer does.
List<String> flowGestureChips(FlowGesture g, {bool? mac}) {
  final s = S.current;
  return [
    ..._modifiers(
      mac ?? flowOnMac,
      primary: g.primary,
      shift: g.shift,
      alt: g.alt,
    ),
    if (g.space) s.scSpace,
    switch (g.pointer) {
      .click => s.scClick,
      .doubleClick => s.scDoubleClick,
      .drag => s.scDrag,
      .dragEmpty => s.scDragEmpty,
      .dragHeader => s.scDragHeader,
      .middleDrag => s.scMiddleDrag,
      .scroll => s.scScroll,
      .wheel => s.scWheel,
      .pinch => s.scPinch,
    },
  ];
}

/// What [command] is called in the card and in the context menu.
String flowCommandLabel(FlowCommand command) {
  final s = S.current;
  return switch (command) {
    .selectAll => s.scSelectAll,
    .marquee => s.scMarquee,
    .addToSelection => s.scAddToSelection,
    .moveSelection => s.scMoveSelection,
    .nudgeLeft || .nudgeRight || .nudgeUp || .nudgeDown => s.scNudge,
    .escape => s.scEscape,
    .copy => s.scCopy,
    .cut => s.scCut,
    .paste => s.scPaste,
    .duplicate => s.scDuplicate,
    .delete => s.scDelete,
    .undo => s.scUndo,
    .redo => s.scRedo,
    .unbind => s.scUnbind,
    .pan => s.scPan,
    .zoom => s.scZoom,
    .zoomIn => s.scZoomIn,
    .zoomOut => s.scZoomOut,
    .zoomReset => s.scZoomReset,
    .zoomFit => s.scZoomFit,
    .viewValue => s.scViewValue,
    .searchPalette => s.scSearchPalette,
    .deploy => s.scDeploy,
    .help => s.scHelp,
    .fields => s.fmFields,
    .unpin => s.fmUnpin,
    .createCustomBlock => s.fmCreateCustom,
    .editCustomBlock => s.fmEditCustom,
  };
}

/// One key of a shortcut as it is printed: a word in mono (`Ctrl`, `Z`,
/// `Enter`), or the icon of a glyph the bundled fonts do not hold (⌘ ⌥ ⇧
/// and the arrows: `key_*` of the icon set).
class KeyGlyph extends StatelessWidget {
  const KeyGlyph(this.token, {required this.color, this.size = 11, super.key});

  final String token;
  final Color color;

  /// The text size; an icon is drawn two points larger.
  final double size;

  static const _icons = {
    '⌘': 'key_cmd',
    '⌥': 'key_alt',
    '⇧': 'key_shift',
    '←': 'key_left',
    '→': 'key_right',
    '↑': 'key_up',
    '↓': 'key_down',
  };

  /// [text] (`⌘⇧Z`, `Ctrl+C`) cut into what [KeyGlyph] draws: each glyph
  /// by itself, the rest together.
  static List<String> tokens(String text) {
    final out = <String>[];
    final rest = StringBuffer();
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      if (_icons.containsKey(ch)) {
        if (rest.isNotEmpty) {
          out.add(rest.toString());
          rest.clear();
        }
        out.add(ch);
      } else {
        rest.write(ch);
      }
    }
    if (rest.isNotEmpty) {
      out.add(rest.toString());
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => switch (_icons[token]) {
    final icon? => AppIcon(icon, size: size + 2, color: color),
    null => Text(
      token,
      style: mono(size: size, color: color).copyWith(height: 1.1),
    ),
  };
}

/// The card of every shortcut of the flow canvas (spec §14): opened by the
/// `?` button beside the legend and by the `?` key, closed by its ×, by
/// Esc, by `?` again or by a click beside it. It prints [flowShortcuts]
/// and nothing else; the four arrows are one row.
class ShortcutCard extends StatelessWidget {
  const ShortcutCard({required this.onClose, this.mac, super.key});

  final VoidCallback onClose;

  /// ⌘ ⌥ ⇧ glyphs (macOS) or `Ctrl` `Alt` `Shift`; null: this machine's.
  final bool? mac;

  static const Set<FlowCommand> _arrows = {
    FlowCommand.nudgeRight,
    FlowCommand.nudgeUp,
    FlowCommand.nudgeDown,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    final m = mac ?? flowOnMac;

    Widget chip(String t) => Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c.ground4,
        border: .all(color: c.line2),
        borderRadius: Radii.chip,
      ),
      child: Center(
        widthFactor: 1,
        child: KeyGlyph(t, color: c.text1),
      ),
    );

    Widget combo(List<String> chips) => Wrap(
      spacing: 3,
      runSpacing: 3,
      alignment: .end,
      children: chips.map(chip).toList(),
    );

    Widget row(FlowShortcut sc) {
      final nudge = sc.command == FlowCommand.nudgeLeft;
      final combos = nudge
          ? [
              ['←', '→', '↑', '↓'],
              [if (m) '⇧' else 'Shift', s.scNudgeFar],
            ]
          : [
              for (final k in sc.keys)
                if (k.listed) flowKeyChips(k, mac: m),
              for (final g in sc.gestures) flowGestureChips(g, mac: m),
            ];
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  flowCommandLabel(sc.command),
                  style: TextStyle(fontSize: 13, color: c.text2),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 216),
              child: Wrap(
                alignment: .end,
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: .center,
                children: [
                  for (final (i, x) in combos.indexed) ...[
                    if (i > 0)
                      Text(
                        nudge ? '·' : s.scOr,
                        style: TextStyle(fontSize: 11, color: c.text4),
                      ),
                    combo(x),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget group(FlowShortcutGroup g) => Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            switch (g) {
              .select => s.scGroupSelect,
              .edit => s.scGroupEdit,
              .view => s.scGroupView,
            }.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: .w600,
              letterSpacing: 0.66,
              color: c.text4,
            ),
          ),
        ),
        for (final sc in flowShortcuts)
          if (sc.group == g && !_arrows.contains(sc.command)) row(sc),
      ],
    );

    return Material(
      color: c.ground2,
      elevation: 12,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.panel,
        side: BorderSide(color: c.line3),
      ),
      clipBehavior: .antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
              decoration: BoxDecoration(
                color: c.ground3,
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.scTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: .w600,
                        color: c.text1,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: s.closeLabel,
                    visualDensity: .compact,
                    onPressed: onClose,
                    icon: AppIcon('ui_close', size: 16, color: c.text3),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Row(
                  crossAxisAlignment: .start,
                  spacing: 28,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: .min,
                        crossAxisAlignment: .stretch,
                        spacing: 16,
                        children: [group(.select), group(.edit)],
                      ),
                    ),
                    Expanded(child: group(.view)),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(
                s.scNote,
                style: TextStyle(fontSize: 12, color: c.text4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
