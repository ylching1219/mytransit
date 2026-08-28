import 'dart:async';

import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

import 'location_service.dart';

LocationService createPlatformLocationService() => IoLocationService();

class IoLocationService implements LocationService {
  final Location _location = Location();
  StreamSubscription<LocationData>? _subscription;

  @override
  Future<LocationStatus> checkStatus() async {
    return LocationStatus(
      gpsEnabled: await _location.serviceEnabled(),
      permissionGranted: await handler.Permission.locationWhenInUse.isGranted,
    );
  }

  @override
  Future<bool> requestGps() => _location.requestService();

  @override
  Future<bool> requestPermission() async {
    final status = await handler.Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  @override
  Future<LocationSnapshot> getCurrentLocation() async {
    final data = await _location.getLocation();
    return LocationSnapshot(latitude: data.latitude, longitude: data.longitude);
  }

  @override
  Future<void> startTracking(void Function(LocationSnapshot) onLocation) async {
    await stopTracking();
    _subscription = _location.onLocationChanged.listen((data) {
      onLocation(
        LocationSnapshot(latitude: data.latitude, longitude: data.longitude),
      );
    });
  }

  @override
  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
