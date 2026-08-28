import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/transit_models.dart';
import 'database_adapter.dart';

DatabaseAdapter createPlatformDatabase() => SqliteDatabaseAdapter();

class SqliteDatabaseAdapter implements DatabaseAdapter {
  Database? _database;
  String _userScope = 'guest';

  static const _databaseFileName = 'MyTransitAssist.db';
  static const _legacyDatabaseFileName = 'smartmove.db';

  @override
  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    final databasePath = path.join(directory.path, _databaseFileName);
    final legacyDatabasePath = path.join(
      directory.path,
      _legacyDatabaseFileName,
    );
    final newDatabase = File(databasePath);
    final legacyDatabase = File(legacyDatabasePath);

    // Migrate old installations, then remove the obsolete database file.
    if (await legacyDatabase.exists()) {
      if (!await newDatabase.exists()) {
        await legacyDatabase.copy(databasePath);
      }
      if (await newDatabase.exists()) {
        await legacyDatabase.delete();
      }
    }

    _database = await openDatabase(
      databasePath,
      version: 2,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE saved_places(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            user_scope TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE journeys(
            id TEXT PRIMARY KEY,
            from_location TEXT NOT NULL,
            to_location TEXT NOT NULL,
            service TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            user_scope TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            "ALTER TABLE saved_places ADD COLUMN user_scope TEXT NOT NULL DEFAULT 'legacy'",
          );
          await database.execute(
            "ALTER TABLE journeys ADD COLUMN user_scope TEXT NOT NULL DEFAULT 'legacy'",
          );
          // Old rows were shared by every account, so they cannot safely be
          // assigned to a specific user.
          await database.delete('saved_places');
          await database.delete('journeys');
        }
      },
    );
  }

  @override
  void setUserScope(String scope) {
    _userScope = scope.trim().isEmpty ? 'guest' : scope.trim();
  }

  Database get _db => _database!;

  @override
  Future<List<SavedPlace>> loadSavedPlaces() async {
    final rows = await _db.query(
      'saved_places',
      where: 'user_scope = ?',
      whereArgs: [_userScope],
    );
    return rows.map(SavedPlace.fromMap).toList();
  }

  @override
  Future<void> saveSavedPlaces(List<SavedPlace> places) async {
    await _db.transaction((transaction) async {
      await transaction.delete(
        'saved_places',
        where: 'user_scope = ?',
        whereArgs: [_userScope],
      );
      for (final place in places) {
        final values = Map<String, Object?>.from(place.toMap());
        values['user_scope'] = _userScope;
        await transaction.insert('saved_places', values);
      }
    });
  }

  @override
  Future<List<JourneyRecord>> loadJourneys() async {
    final rows = await _db.query(
      'journeys',
      where: 'user_scope = ?',
      whereArgs: [_userScope],
      orderBy: 'created_at DESC',
    );
    return rows.map(JourneyRecord.fromMap).toList();
  }

  @override
  Future<void> saveJourneys(List<JourneyRecord> journeys) async {
    await _db.transaction((transaction) async {
      await transaction.delete(
        'journeys',
        where: 'user_scope = ?',
        whereArgs: [_userScope],
      );
      for (final journey in journeys) {
        final values = Map<String, Object?>.from(journey.toMap());
        values['user_scope'] = _userScope;
        await transaction.insert('journeys', values);
      }
    });
  }
}
