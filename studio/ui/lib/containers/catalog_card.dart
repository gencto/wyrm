import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../models/link_run_mode.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One entry of the official list, as typed values: [CatalogCard] words
/// them.
final class CatalogCardVm extends Equatable {
  const CatalogCardVm({
    required this.id,
    required this.tag,
    required this.name,
    required this.description,
    required this.builtIn,
    required this.modes,
    this.existing = 0,
    this.version,
    this.official = false,
    this.selected = false,
  });

  final String id;
  final String tag;
  final String name;
  final String description;

  /// Built into wyrmd; else a package of the repository.
  final bool builtIn;

  /// How it can run.
  final List<LinkRunMode> modes;

  /// Links of it the broker already has.
  final int existing;

  /// `wyrmd 0.1.0`, `1.2.0`; none when the broker does not say.
  final String? version;

  /// The broker says it is an official link (ADR 0043 §5); only then the
  /// card has the mark.
  final bool official;
  final bool selected;

  /// The run modes as the card says them: `embedded · process · external`.
  String get modeCodes => [for (final m in modes) m.code].join(' · ');

  @override
  List<Object?> get props => [
    id,
    tag,
    name,
    description,
    builtIn,
    modes,
    existing,
    version,
    official,
    selected,
  ];
}

/// Board *Add a link · O1*: tag, name, note, one line, the source chip,
/// the official mark, the run modes and the version.
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
                        fontSize: FontSizes.lg,
                        fontWeight: .w600,
                        color: c.text1,
                      ),
                    ),
                  ),
                  if (vm.existing > 0)
                    Text(
                      S.current.linksAlready(vm.existing),
                      style: TextStyle(fontSize: FontSizes.xs, color: c.good),
                    ),
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
                  style: TextStyle(
                    fontSize: FontSizes.sm,
                    height: 1.4,
                    color: c.text3,
                  ),
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
                      vm.builtIn ? S.current.builtIn : S.current.package,
                      style: TextStyle(
                        fontSize: FontSizes.xs,
                        color: vm.builtIn ? c.text2 : c.good,
                      ),
                    ),
                  ),
                  if (vm.official)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.emberFill,
                        borderRadius: Radii.chip,
                      ),
                      child: Row(
                        mainAxisSize: .min,
                        spacing: 3,
                        children: [
                          AppIcon('ui_check', size: 12, color: c.ember),
                          Text(
                            S.current.officialMark,
                            style: TextStyle(
                              fontSize: FontSizes.xs,
                              color: c.ember,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Text(
                      vm.modeCodes,
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
