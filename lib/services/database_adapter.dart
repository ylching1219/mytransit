import '../models/transit_models.dart';
import 'database_adapter_io.dart';

abstract class DatabaseAdapter {
  Future<void> init();
  void setUserScope(String scope);
  Future<List<SavedPlace>> loadSavedPlaces();
  Future<void> saveSavedPlaces(List<SavedPlace> places);
  Future<List<JourneyRecord>> loadJourneys();
  Future<void> saveJourneys(List<JourneyRecord> journeys);
}

DatabaseAdapter createDatabaseAdapter() => createPlatformDatabase();
