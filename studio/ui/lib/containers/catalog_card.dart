import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One entry of the official list.
final class CatalogCardVm extends Equatable {
  const CatalogCardVm({
    required this.id,
    required this.tag,
    required this.name,
    required this.description,
    required this.source,
    required this.builtIn,
    required this.modes,
    this.note,
    this.version,
    this.selected = false,
  });

  final String id;
  final String tag;
  final String name;
  final String description;

  /// `built in` or `package`.
  final String source;
  final bool builtIn;

  /// `embedded · process · external`.
  final String modes;

  /// `1 link already`.
  final String? note;

  /// `wyrmd 0.1.0`, `1.2.0`; none when the broker does not say.
  final String? version;
  final bool selected;

  @override
  List<Object?> get props => [
    id,
    tag,
    name,
    description,
    source,
    builtIn,
    modes,
    note,
    version,
    selected,
  ];
}

/// Board *Add a link · O1*: tag, name, note, one line, the source chip,
/// the run modes and the version.
///
/// Every card is as high as every other (owner 2026-11-11): the name is one
/// line, the description always takes [descriptionLines] lines (more ends in
/// an ellipsis, fewer leave the space), so the bottom row sits at the same
/// place on each card of the grid.
class CatalogCard extends StatelessWidget {
  const CatalogCard({required this.vm, this.onTap, super.key});

  final CatalogCardVm vm;
  final ValueChanged<String>? onTap;

  /// The lines the description takes on every card.
  static const descriptionLines = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: vm.selected ? c.emberFill : c.ground2,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(
          color: vm.selected ? c.ember : c.line1,
          width: vm.selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(vm.id),
        borderRadius: Radii.card,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Row(
                spacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.ground4,
                      borderRadius: Radii.chip,
                    ),
                    child: Text(
                      vm.tag,
                      style: mono(size: 10, weight: .w600, color: c.text2),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      vm.name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: .w600,
                        color: c.text1,
                      ),
                    ),
                  ),
                  if (vm.note case final n?)
                    Text(n, style: TextStyle(fontSize: 11, color: c.good)),
                ],
              ),
              SizedBox(
                // Two lines of 12 × 1.4 at the reader's text scale.
                height:
                    MediaQuery.textScalerOf(context).scale(12) *
                    1.4 *
                    descriptionLines,
                child: Text(
                  vm.description,
                  maxLines: descriptionLines,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.4, color: c.text3),
                ),
              ),
              Row(
                spacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: vm.builtIn ? c.ground4 : c.goodTint,
                      borderRadius: Radii.chip,
                    ),
                    child: Text(
                      vm.source,
                      style: TextStyle(
                        fontSize: 11,
                        color: vm.builtIn ? c.text2 : c.good,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      vm.modes,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: mono(size: 11, color: c.text4),
                    ),
                  ),
                  if (vm.version case final v?)
                    Text(
                      v,
                      maxLines: 1,
                      style: mono(size: 11, color: c.text3),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
