import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/profile_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_profiles_action.dart';

/// `sys/profiles` ▸ `put {name, profile}` (config): [bytes] of [fileName]
/// as the CBOR `ProfileDef` (`.cbor` as it is, JSON encoded first). The
/// broker audits it (`profile_put`). The list is read again.
class PutProfileAction extends Action with NonReentrant, WaitingAction {
  PutProfileAction(this.name, this.fileName, this.bytes);

  final String name;
  final String fileName;
  final Uint8List bytes;

  @override
  Future<AppState?> reduce() async {
    await invokeAll(
      deps.wyrm,
      '${site.root}/sys/profiles',
      'put',
      Value.from({'name': name, 'profile': profileBytes(fileName, bytes)}),
    );
    await dispatchAndWait(RetrieveProfilesAction());
    return null;
  }
}
