import '../models/transit_models.dart';
import 'database_adapter_io.dart'
    if (dart.library.html) 'database_adapter_web.dart';

abstract class DatabaseAdapter {
  Future<void> init();
  void setUserScope(String scope);
  Future<List<SavedPlace>> loadSavedPlaces();
  Future<void> saveSavedPlaces(List<SavedPlace> places);
  Future<List<JourneyRecord>> loadJourneys();
  Future<void> saveJourneys(List<JourneyRecord> journeys);
}

DatabaseAdapter createDatabaseAdapter() => createPlatformDatabase();
