import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/link_install/actions/choose_install_source_action.dart';
import 'package:business/redux/link_install/actions/set_accept_rights_action.dart';
import 'package:business/redux/link_install/actions/set_method_action.dart';
import 'package:business/redux/link_install/actions/set_source_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/install_path.dart';
import 'package:models/install_source.dart';
import 'package:models/package_method.dart';

import 'support/fake_wyrm.dart';

/// Consent is given to one package: the rights accepted for it are
/// accepted no longer once another one is brought, or another way.
void main() {
  late Store<AppState> s;

  setUp(() {
    s = fakeStore()
      ..dispatchSync(ChooseInstallSourceAction(InstallPath.custom))
      ..dispatchSync(
        SetSourceAction(
          InstallSource.zip(bytes: Uint8List(1), fileName: 'a.zip'),
        ),
      )
      ..dispatchSync(SetAcceptRightsAction(true));
  });

  test('another package brought: its rights are not accepted', () {
    expect(s.state.linkInstall.acceptRights, isTrue);
    s.dispatchSync(
      SetSourceAction(
        InstallSource.zip(bytes: Uint8List(2), fileName: 'b.zip'),
      ),
    );
    expect(s.state.linkInstall.acceptRights, isFalse);
  });

  test('another way of bringing it: nothing brought, nothing accepted', () {
    s.dispatchSync(SetMethodAction(PackageMethod.url));
    expect(s.state.linkInstall.source, isNull);
    expect(s.state.linkInstall.acceptRights, isFalse);
  });

  test('the same way again with a consent given: it is taken back', () {
    s
      ..dispatchSync(SetSourceAction(null))
      ..dispatchSync(SetAcceptRightsAction(true))
      ..dispatchSync(SetMethodAction(PackageMethod.zip));
    expect(s.state.linkInstall.acceptRights, isFalse);
  });
}
