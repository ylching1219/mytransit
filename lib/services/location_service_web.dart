import 'location_service.dart';

LocationService createPlatformLocationService() => WebLocationService();

class WebLocationService implements LocationService {
  @override
  Future<LocationStatus> checkStatus() async {
    return const LocationStatus(gpsEnabled: false, permissionGranted: false);
  }

  @override
  Future<bool> requestGps() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> startTracking(
    void Function(LocationSnapshot) onLocation,
  ) async {}

  @override
  Future<void> stopTracking() async {}
}
