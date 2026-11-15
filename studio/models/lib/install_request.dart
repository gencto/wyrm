import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'link_install_call.dart';
import 'link_mode.dart';

part 'install_request.freezed.dart';

/// One install of Add a link, with its arguments typed: what is sent to
/// `sys/links` (docs/links.md §5). `accept` is the user's consent to the
/// rights the package asks for.
@freezed
sealed class InstallRequest with _$InstallRequest {
  const InstallRequest._();

  /// `install {id, driver, mode}`.
  const factory InstallRequest.builtIn({
    required String id,
    required String driver,
    required LinkMode mode,
  }) = InstallBuiltIn;

  /// `install_repo {name, package, accept}`.
  const factory InstallRequest.repository({
    required String name,
    required String package,
    required bool accept,
  }) = InstallRepository;

  /// `install_zip {name, zip, accept}`.
  const factory InstallRequest.zip({
    required String name,
    required Uint8List zip,
    required bool accept,
  }) = InstallZip;

  /// `install_url {name, url, accept}`.
  const factory InstallRequest.url({
    required String name,
    required String url,
    required bool accept,
  }) = InstallUrl;

  /// `install_git {name, url, ref, accept}`.
  const factory InstallRequest.git({
    required String name,
    required String url,
    required bool accept,
    String? ref,
  }) = InstallGit;

  /// `install_wasm {name, wasm, accept}`.
  const factory InstallRequest.wasm({
    required String name,
    required Uint8List wasm,
    required bool accept,
  }) = InstallWasm;

  /// `install_backup {upload, id, accept, passphrase}`.
  const factory InstallRequest.backup({
    required String upload,
    required String id,
    required bool accept,
    String? passphrase,
  }) = InstallBackup;

  /// The action of `sys/links` it is.
  LinkInstallCall get call => switch (this) {
    InstallBuiltIn() => LinkInstallCall.builtIn,
    InstallRepository() => LinkInstallCall.repository,
    InstallZip() => LinkInstallCall.zip,
    InstallUrl() => LinkInstallCall.url,
    InstallGit() => LinkInstallCall.git,
    InstallWasm() => LinkInstallCall.wasm,
    InstallBackup() => LinkInstallCall.backup,
  };
}
