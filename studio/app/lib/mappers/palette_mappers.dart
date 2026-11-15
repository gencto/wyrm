import 'package:models/palette_tab.dart';

/// The id a palette tab has among the flow editor's tabs (`TabItemVm.id`,
/// the key the page gives back on a tap).
extension PaletteTabId on PaletteTab {
  String get tabId => switch (this) {
    PaletteTab.blocks => 'blocks',
    PaletteTab.my => 'my',
    PaletteTab.tree => 'tree',
  };
}

/// The palette tab of the tab id [id] ([PaletteTabId.tabId]); null for any
/// other id.
PaletteTab? paletteTabOfId(String id) =>
    PaletteTab.values.where((t) => t.tabId == id).firstOrNull;
