import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:models/system_notice.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/profile_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/show_notice_action.dart';
import 'retrieve_profiles_action.dart';

/// `sys/profiles` ▸ `put {name, profile}` (config): [bytes] of [fileName]
/// as the CBOR `ProfileDef` (`.cbor` as it is, JSON encoded first). The
/// broker audits it (`profile_put`). The list is read again,
/// and a toast says so.
class PutProfileAction extends Action with NonReentrant, WaitingAction {
  PutProfileAction(this.name, this.fileName, this.bytes);

  @override
  Action again() => PutProfileAction(name, fileName, bytes);

  @override
  Action reload() => RetrieveProfilesAction();

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
    await dispatchAndWait(
      ShowNoticeAction.system(SystemNotice.profilePut(name)),
    );
    return null;
  }
}
