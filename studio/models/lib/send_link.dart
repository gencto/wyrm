import 'package:freezed_annotation/freezed_annotation.dart';

part 'send_link.freezed.dart';

@freezed
abstract class SendLink with _$SendLink {
  /// A file-store link the host lets backups go to (`backups.send_links`,
  /// attribute `send_links` of `sys/backups`), with the folder it named.
  const factory SendLink({
    required String link,
    @Default('backups') String folder,
  }) = _SendLink;
}
