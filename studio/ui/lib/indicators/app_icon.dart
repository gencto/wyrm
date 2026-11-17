import 'package:material_ui/material_ui.dart';

/// Every icon Studio draws, and where its drawing comes from: one of the
/// canvas set (`ui/assets/svg/icons/<asset>.svg`, 24×24, stroke 1.8,
/// `currentColor`) or, where the set has no drawing yet, a Material glyph.
/// A widget, a render model and a mapper name an icon by its case here,
/// never by a file name or an `IconData`; `AppIconView` draws it.
///
/// Cases by prefix (docs/studio.md §6.4): `ws` workspaces of the rail,
/// `node` tree node kinds, `mode` link run modes, `action` link actions,
/// `ui` controls, `err` the error surfaces, `key` keys of a shortcut,
/// `material` the glyphs not drawn in the set.
enum AppIcon {
  // Actions on a link, a site, a row.
  actionBlock('action_block'),
  actionEdit('action_edit'),
  actionGrant('action_grant'),
  actionHist('action_hist'),
  actionKey('action_key'),
  actionLock('action_lock'),
  actionLog('action_log'),
  actionPlay('action_play'),
  actionStop('action_stop'),
  actionTrash('action_trash'),
  actionUp('action_up'),

  // The error surfaces (docs/design/specs/errors.md).
  errBroker('err_broker'),
  errBusy('err_busy'),
  errChevron('err_chevron'),
  errClose('err_close'),
  errCopy('err_copy'),
  errGone('err_gone'),
  errInput('err_input'),
  errMark('err_mark'),
  errOk('err_ok'),
  errReach('err_reach'),
  errRights('err_rights'),
  errStudio('err_studio'),
  errWarn('err_warn'),

  // Keys of a shortcut.
  keyAlt('key_alt'),
  keyCmd('key_cmd'),
  keyDown('key_down'),
  keyLeft('key_left'),
  keyRight('key_right'),
  keyShift('key_shift'),
  keyUp('key_up'),

  // How a link runs.
  modeEmbedded('mode_embedded'),
  modeExternal('mode_external'),
  modeProcess('mode_process'),
  modeWasm('mode_wasm'),

  // What a node of the tree is.
  nodeAction('node_action'),
  nodeConn('node_conn'),
  nodeDevice('node_device'),
  nodeFlow('node_flow'),
  nodeLink('node_link'),
  nodePoint('node_point'),
  nodeProfile('node_profile'),
  nodeSection('node_section'),
  nodeSite('node_site'),
  nodeStorage('node_storage'),
  nodeSys('node_sys'),
  nodeWatch('node_watch'),

  // Controls.
  uiAdd('ui_add'),
  uiBind('ui_bind'),
  uiCheck('ui_check'),
  uiChevronDown('ui_chevron_down'),
  uiChevronRight('ui_chevron_right'),
  uiClose('ui_close'),
  uiCopy('ui_copy'),
  uiFile('ui_file'),
  uiFilter('ui_filter'),
  uiMaximize('ui_maximize'),
  uiMinimize('ui_minimize'),
  uiMoon('ui_moon'),
  uiMore('ui_more'),
  uiPin('ui_pin'),
  uiProfile('ui_profile'),
  uiRestore('ui_restore'),
  uiSearch('ui_search'),
  uiSend('ui_send'),
  uiSpinner('ui_spinner'),
  uiSun('ui_sun'),
  uiUpload('ui_upload'),
  uiView('ui_view'),

  // Workspaces of the rail.
  wsAccess('ws_access'),
  wsAssistant('ws_assistant'),
  wsExplorer('ws_explorer'),
  wsFlows('ws_flows'),
  wsHistory('ws_history'),
  wsLinks('ws_links'),
  wsSites('ws_sites'),
  wsSystem('ws_system'),

  // Material glyphs: not in the canvas set yet.
  materialCheck.glyph(Icons.check),
  materialMixed.glyph(Icons.remove),
  materialMore.glyph(Icons.more_horiz),
  materialLock.glyph(Icons.lock_outline),
  materialClose.glyph(Icons.close),
  materialAdd.glyph(Icons.add),
  materialShow.glyph(Icons.visibility),
  materialHide.glyph(Icons.visibility_off);

  const AppIcon(String this.asset) : glyph = null;
  const AppIcon.glyph(IconData this.glyph) : asset = null;

  /// The file name without `.svg`, of an icon of the canvas set.
  final String? asset;

  /// The Material glyph, of an icon the set does not draw.
  final IconData? glyph;

  /// The icons of the canvas set, in the order of their families.
  static final List<AppIcon> canvas = [
    for (final i in values)
      if (i.asset != null) i,
  ];
}
