import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'install_source.freezed.dart';

/// Where a new link comes from (docs/studio.md §7.3).
@freezed
sealed class InstallSource with _$InstallSource {
  /// A driver built into the broker: `install {driver}`.
  const factory InstallSource.builtIn({required String driver}) =
      InstallSourceBuiltIn;

  /// A package of the repository: `install_repo {package}`.
  const factory InstallSource.repository({
    required String package,
    String? version,
  }) = InstallSourceRepository;

  /// A package zip picked from disk: `install_zip {zip}`.
  const factory InstallSource.zip({
    required Uint8List bytes,
    required String fileName,
  }) = InstallSourceZip;

  /// A package zip at a URL: `install_url {url}`.
  const factory InstallSource.url({required String url}) = InstallSourceUrl;

  /// A Git repository with a built package: `install_git {url, ref}`.
  const factory InstallSource.git({required String url, String? ref}) =
      InstallSourceGit;

  /// A link backup picked from disk (`.wyrm-link`, ADR 0048 §3.5):
  /// uploaded in parts, then `install_backup {upload}`. Only its name and
  /// size are here: the file is read in parts through the handle the wizard
  /// holds, and its bytes are in no state.
  const factory InstallSource.backup({
    required String fileName,
    required int size,
  }) = InstallSourceBackup;

  /// One WASM component: `install_wasm {wasm}`.
  const factory InstallSource.wasm({
    required Uint8List bytes,
    required String fileName,
  }) = InstallSourceWasm;
}
