import 'location_service_io.dart';

class LocationSnapshot {
  final double? latitude;
  final double? longitude;

  const LocationSnapshot({this.latitude, this.longitude});
}

class LocationStatus {
  final bool gpsEnabled;
  final bool permissionGranted;

  const LocationStatus({
    required this.gpsEnabled,
    required this.permissionGranted,
  });
}

abstract class LocationService {
  Future<LocationStatus> checkStatus();
  Future<bool> requestGps();
  Future<bool> requestPermission();
  Future<LocationSnapshot> getCurrentLocation();
  Future<void> startTracking(void Function(LocationSnapshot) onLocation);
  Future<void> stopTracking();
}

LocationService createLocationService() => createPlatformLocationService();
