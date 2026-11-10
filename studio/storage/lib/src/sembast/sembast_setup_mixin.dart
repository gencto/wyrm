import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import 'sembast.dart';

mixin SembastSetupMixin {
  Database? _db;

  Database get db {
    if (_db == null) {
      throw StateError('Database is not initialized. Call setupStorage first.');
    }
    return _db!;
  }

  StoreRef get mainStore => StoreRef.main();

  /// The path of the database file, once [setupStorage] has resolved it
  /// (also when opening it then failed).
  String? get path => _path;
  String? _path;

  /// Opens (or creates) [dbFile] in the documents directory, or in
  /// [directory] when given (tests, which have no path_provider).
  ///
  /// A file that exists and is not a database is an error, not a reason to
  /// start over: sembast's default mode would delete it and lose the user's
  /// settings without a word, so the file is opened with
  /// `DatabaseMode.create`, which throws.
  Future<void> setupStorage({
    String dbFile = 'database.db',
    String? password,
    String? directory,
  }) async {
    final getPath = () async {
      //
      // ignore: do_not_use_environment
      const isWeb = bool.fromEnvironment('dart.library.js_util');

      if (directory != null) {
        return p.join(directory, dbFile);
      }

      if (!isWeb) {
        final dir = await getApplicationDocumentsDirectory();
        await dir.create(recursive: true);
        final dbPath = p.join(dir.path, dbFile);

        return dbPath;
      }

      return '/assets/db';
    }();

    final dbPath = await getPath;
    _path = dbPath;

    final dbFactory = getDatabaseFactory();

    _db = await dbFactory.openDatabase(
      dbPath,
      mode: DatabaseMode.create,
      codec: password != null
          ? getEncryptSembastCodec(password: password)
          : null,
    );
  }
}
