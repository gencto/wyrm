import 'package:localization/localization.dart';

/// How a link runs, as drawn: its [code] (the mode's own name, shown in
/// mono on a card of the official list), its label and one line of what
/// it means.
enum LinkRunMode {
  embedded('embedded'),
  process('process'),
  external('external'),
  wasm('wasm');

  const LinkRunMode(this.code);

  final String code;

  String get label => switch (this) {
    embedded => S.current.modeEmbedded,
    process => S.current.modeProcess,
    external => S.current.modeExternal,
    wasm => 'WASM',
  };

  String get note => switch (this) {
    embedded => S.current.modeEmbeddedNote,
    process => S.current.modeProcessNote,
    external => S.current.modeExternalNote,
    wasm => S.current.modeWasmNote,
  };
}
