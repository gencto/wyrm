import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One icon of the canvas set (`ui/assets/svg/icons/<name>.svg`, 24×24,
/// stroke 1.8, `currentColor`), tinted with [color] or the current
/// `IconTheme`.
///
/// Names by prefix (docs/studio.md §6.4): `ws_` workspaces of the rail,
/// `node_` tree node kinds, `mode_` link run modes, `action_` link actions,
/// `ui_` controls.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {this.size = 20, this.color, super.key});

  /// The file name without `.svg`, e.g. `ws_links`.
  final String name;

  /// 16, 20 or 24.
  final double size;

  final Color? color;

  /// The one `node_` glyph of a node's kind (board *Icons* "What a node is"),
  /// the same in every tree, search result and breadcrumb. [key] is the
  /// node's full key under the site [root] (`wy/<site>`), [profile] its `is`
  /// and [type] its value type (null for a node that is not a value).
  static String nodeName({
    required String key,
    required String root,
    String? profile,
    String? type,
  }) {
    if (type != null) {
      return 'node_point';
    }
    if (key == root) {
      return 'node_site';
    }
    final rel = key.startsWith('$root/') ? key.substring(root.length + 1) : key;
    final parts = rel.split('/');
    final section = parts.first;
    final p = profile ?? '';
    if (parts.length == 1) {
      return section == 'sys' ? 'node_sys' : 'node_section';
    }
    return switch (p) {
      'wy:broker' => 'node_site',
      'wy:link' => 'node_link',
      'wy:flow' => 'node_flow',
      _ when section == 'upstream' && parts.length == 2 => 'node_site',
      _ when section == 'downstream' && parts.length == 2 => 'node_link',
      _ when section == 'dataflows' && parts.length == 2 => 'node_flow',
      _ when section == 'pub' => 'node_profile',
      _ when p.contains('watch') => 'node_watch',
      _ when section == 'sys' => 'node_sys',
      _ when section == 'storage' => 'node_storage',
      _ when p.contains('conn') => 'node_conn',
      _ when p.contains('device') => 'node_device',
      // A device model profile is `<vendor>:<model>`.
      _ when p.contains(':') && !p.startsWith('wy:') => 'node_device',
      _ => 'node_section',
    };
  }

  /// The type tag a point carries beside its name (board *Icons* "Point:
  /// add its type tag"): `.0` number, `01` bool, `Aa` string, `≡` enum,
  /// `{}` a structure, `0x` binary.
  static String typeTag(String? type) => switch (type) {
    'number' => '.0',
    'bool' => '01',
    'string' => 'Aa',
    'enum' => '≡',
    'map' || 'array' || 'dynamic' => '{}',
    'binary' => '0x',
    _ => '·',
  };

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? Colors.white;
    return SvgPicture.asset(
      'assets/svg/icons/$name.svg',
      package: 'ui',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
