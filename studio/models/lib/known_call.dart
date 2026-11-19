import 'call_verb.dart';

/// The calls Studio names in an error: each with its wire name (what
/// *key › call* shows, and what an action is invoked by) and its
/// [CallVerb]. A call that is not here is any action of a link, carried by
/// its own name (`ErrorCall.named`).
enum KnownCall {
  deploy('deploy', CallVerb.deploy),
  install('install', CallVerb.install),
  installRepo('install_repo', CallVerb.install),
  installZip('install_zip', CallVerb.install),
  installUrl('install_url', CallVerb.install),
  installGit('install_git', CallVerb.install),
  installWasm('install_wasm', CallVerb.install),
  set('set', CallVerb.write),
  list('list', CallVerb.list),
  meta('meta', CallVerb.read),
  subscribe('subscribe', CallVerb.read),
  history('history', CallVerb.read),
  getLog('get_log', CallVerb.read),
  getBlock('get_block', CallVerb.read),
  getDef('get_def', CallVerb.read),
  nodeTypes('node_types', CallVerb.read),
  tail('tail', CallVerb.read),
  users('users', CallVerb.read),
  me('me', CallVerb.read),
  read('read', CallVerb.read),
  remove('remove', CallVerb.remove),
  removeUser('remove_user', CallVerb.remove),
  reject('reject', CallVerb.remove),
  put('put', CallVerb.save),
  putBlock('put_block', CallVerb.save),
  edit('edit', CallVerb.save),
  update('update', CallVerb.save),
  updatePermissions('update_permissions', CallVerb.save),
  saveUser('save_user', CallVerb.save),
  grant('grant', CallVerb.save),
  add('add', CallVerb.save),
  start('start', CallVerb.start),
  stop('stop', CallVerb.stop),
  open('open', CallVerb.open),
  logIn('log_in', CallVerb.logIn),
  // Named by Studio, said as any other action is (`run ask on assistant`).
  encode('encode', CallVerb.run),
  ask('ask', CallVerb.run),
  answer('answer', CallVerb.run),
  approve('approve', CallVerb.run),
  doc('doc', CallVerb.run),
  devices('devices', CallVerb.run),
  signOut('sign_out', CallVerb.run),
  enableDevice('enable_device', CallVerb.run),
  probeRange('probe_range', CallVerb.run),
  trigger('trigger', CallVerb.run),
  downloadPart('download_part', CallVerb.run);

  const KnownCall(this.wire, this.verb);

  /// The name on the wire.
  final String wire;
  final CallVerb verb;

  /// The call named [wire], or null: any other action.
  static KnownCall? fromWire(String wire) =>
      values.where((c) => c.wire == wire).firstOrNull;
}
