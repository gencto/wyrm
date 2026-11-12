import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What a node of the map is, which decides its row and its look.
enum SiteNodeKind {
  /// A broker above the site (row 0).
  upstream,

  /// A platform the site sends to (row 0, dotted line).
  platform,

  /// The site on screen (row 1).
  self,

  /// A broker below (row 2).
  downstream,

  /// A broker that waits in quarantine (row 2, dashed amber).
  waitingBroker,

  /// A device of an external link (row 2, a pill).
  device,

  /// A link that waits in quarantine (row 2, a dashed pill).
  waitingLink,

  /// A site relayed by a broker below (row 3, dashed).
  relayed,
}

/// One node of the map.
final class SiteNodeVm extends Equatable {
  const SiteNodeVm({
    required this.id,
    required this.name,
    required this.kind,
    this.sub = '',
    this.parent,
    this.offline = false,
    this.tag,
    this.selected = false,
  });

  final String id;
  final String name;
  final SiteNodeKind kind;
  final String sub;

  /// The node it hangs from (its edge); the self node for most.
  final String? parent;
  final bool offline;

  /// `YOU`, `MQTT`.
  final String? tag;
  final bool selected;

  bool get waiting =>
      kind == SiteNodeKind.waitingBroker || kind == SiteNodeKind.waitingLink;

  bool get small =>
      kind == SiteNodeKind.device || kind == SiteNodeKind.waitingLink;

  int get row => switch (kind) {
    .upstream || .platform => 0,
    .self => 1,
    .relayed => 3,
    _ => 2,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    kind,
    sub,
    parent,
    offline,
    tag,
    selected,
  ];
}

/// Board *Studio · Sites*: a layered map drawn from data (upstreams and
/// platforms above, the site, the brokers, devices and waiting connections
/// below, relayed sites under their relay). Edges are solid when connected,
/// dashed when offline or waiting, dotted to platforms.
class SiteMap extends StatelessWidget {
  const SiteMap({required this.nodes, required this.onTap, super.key});

  final List<SiteNodeVm> nodes;
  final ValueChanged<String> onTap;

  static const _rowY = [0.0, 110.0, 230.0, 350.0];
  static const _gap = 18.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final rows = <int, List<SiteNodeVm>>{};
        for (final n in nodes) {
          (rows[n.row] ??= []).add(n);
        }
        final pos = <String, Rect>{};
        for (final MapEntry(key: row, value: list) in rows.entries) {
          final sizes = [for (final n in list) _size(n)];
          final widths = sizes.fold<double>(0, (s, z) => s + z.width);
          final total = widths + _gap * (list.length - 1);
          final scale = total > width ? width / total : 1.0;
          var x = math.max<double>(0, (width - total * scale) / 2);
          for (final (i, n) in list.indexed) {
            final w = sizes[i].width * scale;
            final h = sizes[i].height;
            final top = _rowY[row] + (row == 2 && n.small ? 8 : 0);
            pos[n.id] = Rect.fromLTWH(x, top, w, h);
            x += w + _gap * scale;
          }
        }
        final height = rows.keys.isEmpty
            ? 120.0
            : _rowY[rows.keys.reduce(math.max)] + 80;
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _Edges(nodes: nodes, pos: pos, c: c),
                ),
              ),
              for (final n in nodes)
                if (pos[n.id] case final r?)
                  Positioned.fromRect(
                    rect: r,
                    child: _Card(vm: n, onTap: onTap),
                  ),
            ],
          ),
        );
      },
    );
  }

  static Size _size(SiteNodeVm n) =>
      n.small ? const Size(150, 44) : const Size(176, 60);
}

class _Card extends StatelessWidget {
  const _Card({required this.vm, required this.onTap});

  final SiteNodeVm vm;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final self = vm.kind == SiteNodeKind.self;
    final relayed = vm.kind == SiteNodeKind.relayed;
    final border = vm.selected
        ? BorderSide(color: c.ember, width: 1.5)
        : (vm.waiting
              ? BorderSide(color: c.warnLine)
              : BorderSide(
                  color: self ? c.emberLine : (relayed ? c.line3 : c.line2),
                  width: self ? 1.5 : 1,
                ));
    final bg = vm.selected
        ? c.emberFill
        : (vm.waiting
              ? c.warnTint
              : (relayed || vm.kind == SiteNodeKind.upstream
                    ? c.ground1
                    : c.ground2));
    final radius = BorderRadius.circular(vm.small ? 22 : 10);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: radius, side: border),
      child: InkWell(
        onTap: () => onTap(vm.id),
        borderRadius: radius,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: vm.small ? 14 : 12),
          child: Column(
            mainAxisAlignment: .center,
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Row(
                spacing: 8,
                children: [
                  StateMark(
                    mark: vm.waiting ? Mark.ring : Mark.dot,
                    color: vm.waiting
                        ? c.warn
                        : (vm.offline ? c.muted : c.good),
                  ),
                  Flexible(
                    child: Text(
                      vm.name,
                      overflow: .ellipsis,
                      style: mono(
                        size: vm.small ? 12 : 14,
                        weight: .w600,
                        color: c.text1,
                      ),
                    ),
                  ),
                  if (vm.tag case final t?)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: self ? c.emberTint : c.ground4,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        t,
                        style: mono(
                          size: 10,
                          weight: .w600,
                          color: self ? c.emberSoft : c.text2,
                        ),
                      ),
                    ),
                ],
              ),
              if (vm.sub.isNotEmpty && !vm.small)
                Text(
                  vm.sub,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: 12, color: c.text4),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Edges extends CustomPainter {
  _Edges({required this.nodes, required this.pos, required this.c});

  final List<SiteNodeVm> nodes;
  final Map<String, Rect> pos;
  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in nodes) {
      final p = n.parent == null ? null : pos[n.parent];
      final me = pos[n.id];
      if (p == null || me == null) {
        continue;
      }
      final (up, down) = p.top < me.top ? (p, me) : (me, p);
      final a = Offset(up.center.dx, up.bottom);
      final b = Offset(down.center.dx, down.top);
      final my = (a.dy + b.dy) / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, my, b.dx, my, b.dx, b.dy);
      final (color, dash) = switch (n) {
        _ when n.kind == SiteNodeKind.platform => (c.good, (2.0, 5.0)),
        _ when n.waiting => (c.warn, (6.0, 5.0)),
        _ when n.offline => (c.muted, (6.0, 5.0)),
        _ => (c.good, null),
      };
      final paint = Paint()
        ..color = color
        ..style = .stroke
        ..strokeWidth = 1.5;
      if (dash == null) {
        canvas.drawPath(path, paint);
      } else {
        for (final m in path.computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            canvas.drawPath(m.extractPath(d, d + dash.$1), paint);
            d += dash.$1 + dash.$2;
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Edges old) => old.nodes != nodes || old.pos != pos;
}

/// The legend under the map's title.
class SiteLegend extends StatelessWidget {
  const SiteLegend({required this.labels, super.key});

  /// connected, offline, waiting in quarantine, platform.
  final (String, String, String, String) labels;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(Color color, bool dashed, bool dotted, String t) => Row(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        SizedBox(
          width: 22,
          height: 2,
          child: CustomPaint(
            painter: _Line(color, dashed ? 5 : (dotted ? 2 : 0)),
          ),
        ),
        Text(t, style: TextStyle(fontSize: 12, color: c.text3)),
      ],
    );
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        item(c.good, false, false, labels.$1),
        item(c.muted, true, false, labels.$2),
        item(c.warn, true, false, labels.$3),
        item(c.good, false, true, labels.$4),
      ],
    );
  }
}

class _Line extends CustomPainter {
  _Line(this.color, this.dash);

  final Color color;
  final double dash;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    if (dash == 0) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        p,
      );
      return;
    }
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + dash, size.width), size.height / 2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Line old) => old.color != color || old.dash != dash;
}

/// A tone for a site node's state word.
Tone siteTone(SiteNodeVm n) =>
    n.waiting ? Tone.warn : (n.offline ? Tone.neutral : Tone.good);
