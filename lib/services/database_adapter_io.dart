import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/transit_models.dart';
import 'database_adapter.dart';

DatabaseAdapter createPlatformDatabase() => SqliteDatabaseAdapter();

class SqliteDatabaseAdapter implements DatabaseAdapter {
  Database? _database;

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
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE saved_places(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE journeys(
            id TEXT PRIMARY KEY,
            from_location TEXT NOT NULL,
            to_location TEXT NOT NULL,
            service TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Database get _db => _database!;

  @override
  Future<List<SavedPlace>> loadSavedPlaces() async {
    final rows = await _db.query('saved_places');
    return rows.map(SavedPlace.fromMap).toList();
  }

  @override
  Future<void> saveSavedPlaces(List<SavedPlace> places) async {
    await _db.transaction((transaction) async {
      await transaction.delete('saved_places');
      for (final place in places) {
        await transaction.insert('saved_places', place.toMap());
      }
    });
  }

  @override
  Future<List<JourneyRecord>> loadJourneys() async {
    final rows = await _db.query('journeys', orderBy: 'created_at DESC');
    return rows.map(JourneyRecord.fromMap).toList();
  }

  @override
  Future<void> saveJourneys(List<JourneyRecord> journeys) async {
    await _db.transaction((transaction) async {
      await transaction.delete('journeys');
      for (final journey in journeys) {
        await transaction.insert('journeys', journey.toMap());
      }
    });
  }
}
