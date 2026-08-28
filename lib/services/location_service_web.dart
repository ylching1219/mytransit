import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'location_service.dart';

LocationService createPlatformLocationService() => WebLocationService();

class WebLocationService implements LocationService {
  @override
  Future<LocationStatus> checkStatus() async {
    return const LocationStatus(gpsEnabled: true, permissionGranted: true);
  }

  @override
  Future<bool> requestGps() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<LocationSnapshot> getCurrentLocation() async {
    final completer = Completer<LocationSnapshot>();
    final success = ((web.GeolocationPosition position) {
      final coordinates = position.coords;
      completer.complete(
        LocationSnapshot(
          latitude: coordinates.latitude,
          longitude: coordinates.longitude,
        ),
      );
    }).toJS;
    final failure = ((web.GeolocationPositionError error) {
      completer.completeError(Exception(error.message));
    }).toJS;
    web.window.navigator.geolocation.getCurrentPosition(
      success,
      failure,
      web.PositionOptions(
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 30000,
      ),
    );
    return completer.future;
  }

  @override
  Future<void> startTracking(
    void Function(LocationSnapshot) onLocation,
  ) async {}

  @override
  Future<void> stopTracking() async {}
}
