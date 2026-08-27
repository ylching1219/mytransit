import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transit_models.dart';
import 'database_adapter.dart';

DatabaseAdapter createPlatformDatabase() => WebDatabaseAdapter();

class WebDatabaseAdapter implements DatabaseAdapter {
  SharedPreferences? _preferences;

  @override
  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
  }

  SharedPreferences get _prefs => _preferences!;

  @override
  Future<List<SavedPlace>> loadSavedPlaces() async {
    final values = _prefs.getStringList('saved_places') ?? <String>[];
    return values
        .map(
          (value) => SavedPlace.fromMap(
            Map<String, Object?>.from(jsonDecode(value) as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> saveSavedPlaces(List<SavedPlace> places) async {
    await _prefs.setStringList(
      'saved_places',
      places.map((place) => jsonEncode(place.toMap())).toList(),
    );
  }

  @override
  Future<List<JourneyRecord>> loadJourneys() async {
    final values = _prefs.getStringList('journeys') ?? <String>[];
    return values
        .map(
          (value) => JourneyRecord.fromMap(
            Map<String, Object?>.from(jsonDecode(value) as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> saveJourneys(List<JourneyRecord> journeys) async {
    await _prefs.setStringList(
      'journeys',
      journeys.map((journey) => jsonEncode(journey.toMap())).toList(),
    );
  }
}
