import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transit_models.dart';
import 'database_adapter.dart';

DatabaseAdapter createPlatformDatabase() => WebDatabaseAdapter();

class WebDatabaseAdapter implements DatabaseAdapter {
  SharedPreferences? _preferences;
  String _userScope = 'guest';

  @override
  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
    // These keys belong to the old shared storage and could expose one
    // account's data to another, so they are intentionally discarded.
    await _prefs.remove('saved_places');
    await _prefs.remove('journeys');
  }

  @override
  void setUserScope(String scope) {
    _userScope = scope.trim().isEmpty ? 'guest' : scope.trim();
  }

  String get _savedPlacesKey => 'saved_places_$_userScope';
  String get _journeysKey => 'journeys_$_userScope';

  SharedPreferences get _prefs => _preferences!;

  @override
  Future<List<SavedPlace>> loadSavedPlaces() async {
    final values = _prefs.getStringList(_savedPlacesKey) ?? <String>[];
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
      _savedPlacesKey,
      places.map((place) => jsonEncode(place.toMap())).toList(),
    );
  }

  @override
  Future<List<JourneyRecord>> loadJourneys() async {
    final values = _prefs.getStringList(_journeysKey) ?? <String>[];
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
      _journeysKey,
      journeys.map((journey) => jsonEncode(journey.toMap())).toList(),
    );
  }
}
