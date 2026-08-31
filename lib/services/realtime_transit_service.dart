import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;

import 'transit_data_service.dart';

class RealtimeTransitVehicle {
  final String id;
  final String mode;
  final String? routeId;
  final String? currentStopId;
  final String? currentStopName;
  final bool currentStopEstimated;
  final String label;
  final double latitude;
  final double longitude;

  const RealtimeTransitVehicle({
    required this.id,
    required this.mode,
    required this.routeId,
    required this.currentStopId,
    required this.currentStopName,
    this.currentStopEstimated = false,
    required this.label,
    required this.latitude,
    required this.longitude,
  });
}

class RealtimeTransitSnapshot {
  final List<RealtimeTransitVehicle> vehicles;
  final DateTime fetchedAt;
  final String? errorMessage;

  const RealtimeTransitSnapshot({
    required this.vehicles,
    required this.fetchedAt,
    this.errorMessage,
  });
}

class RealtimeTransitService {
  static final _busEndpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl',
  );
  final http.Client _client;

  RealtimeTransitService({http.Client? client})
    : _client = client ?? http.Client();

  Future<RealtimeTransitSnapshot> fetchForRoute(
    TransitRouteResult route,
  ) async {
    final transitLegs = route.legs.where((leg) => !leg.isWalking).toList();
    final modes = <String>{
      for (final leg in transitLegs) leg.mode,
      if (transitLegs.isEmpty) route.mode,
    };
    final routeIds = <String>{
      if (route.routeId != null && route.routeId!.trim().isNotEmpty)
        _normalise(route.routeId!),
      for (final leg in transitLegs)
        if (leg.routeId != null && leg.routeId!.trim().isNotEmpty)
          _normalise(leg.routeId!),
    };
    final routeStations = _stationsForRoute(route);

    final wantsBus = modes.contains('Bus') || modes.contains('Mixed');
    final wantsRail =
        modes.contains('LRT') ||
        modes.contains('MRT') ||
        modes.contains('Rail') ||
        modes.contains('Mixed');
    final requests = <Future<_RealtimeFeedResult>>[];
    if (wantsBus) {
      requests.add(_fetchFeed(_busEndpoint, routeStations));
    }

    if (requests.isEmpty) {
      return RealtimeTransitSnapshot(
        vehicles: const [],
        fetchedAt: DateTime.now(),
        errorMessage: wantsRail
            ? 'Live rail positions are not currently published by the official feed.'
            : 'No live transit feed is available for this route.',
      );
    }

    final results = await Future.wait(requests);
    final vehicles = <RealtimeTransitVehicle>[];
    final seenIds = <String>{};
    String? firstError;

    for (final result in results) {
      firstError ??= result.error;
      for (final vehicle in result.vehicles) {
        if (routeIds.isNotEmpty &&
            (vehicle.routeId == null ||
                !routeIds.contains(_normalise(vehicle.routeId!)))) {
          continue;
        }
        if (seenIds.add(vehicle.id)) vehicles.add(vehicle);
      }
    }

    final feedWarning =
        firstError ??
        (wantsRail && wantsBus
            ? 'Live rail positions are not currently published by the official feed. Live bus positions are shown when available.'
            : null);
    return RealtimeTransitSnapshot(
      vehicles: vehicles,
      fetchedAt: DateTime.now(),
      errorMessage: feedWarning,
    );
  }

  Future<_RealtimeFeedResult> _fetchFeed(
    Uri endpoint,
    List<TransitStationPoint> routeStations,
  ) async {
    const mode = 'Bus';
    try {
      final response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return _RealtimeFeedResult(
          vehicles: const [],
          error: 'Live bus data is temporarily unavailable.',
        );
      }

      final feed = FeedMessage.fromBuffer(response.bodyBytes);
      final vehicles = <RealtimeTransitVehicle>[];

      for (final entity in feed.entity) {
        if (!entity.hasVehicle()) continue;
        final vehiclePosition = entity.vehicle;
        if (!vehiclePosition.hasPosition()) continue;
        final position = vehiclePosition.position;
        if (!position.hasLatitude() || !position.hasLongitude()) continue;
        if (position.latitude == 0 || position.longitude == 0) continue;

        final routeId =
            vehiclePosition.hasTrip() && vehiclePosition.trip.hasRouteId()
            ? vehiclePosition.trip.routeId
            : null;
        final feedStopId = vehiclePosition.hasStopId()
            ? vehiclePosition.stopId
            : null;
        final exactStop = _findStopById(routeStations, feedStopId);
        final nearestStop = exactStop == null
            ? _nearestStop(routeStations, position.latitude, position.longitude)
            : null;
        final currentStop = exactStop ?? nearestStop;
        final vehicleId =
            vehiclePosition.hasVehicle() && vehiclePosition.vehicle.hasId()
            ? vehiclePosition.vehicle.id
            : entity.id;
        final label =
            vehiclePosition.hasVehicle() && vehiclePosition.vehicle.hasLabel()
            ? vehiclePosition.vehicle.label
            : routeId ?? (mode == 'Bus' ? 'Live bus' : 'Live train');
        vehicles.add(
          RealtimeTransitVehicle(
            id: vehicleId.isEmpty ? entity.id : vehicleId,
            mode: mode,
            routeId: routeId,
            currentStopId: currentStop?.id ?? feedStopId,
            currentStopName: currentStop?.name,
            currentStopEstimated: exactStop == null && currentStop != null,
            label: label,
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        );
      }

      return _RealtimeFeedResult(vehicles: vehicles);
    } catch (_) {
      return _RealtimeFeedResult(
        vehicles: const [],
        error: 'Live bus data is temporarily unavailable.',
      );
    }
  }

  void dispose() => _client.close();

  static String _normalise(String value) => value.trim().toLowerCase();

  static List<TransitStationPoint> _stationsForRoute(TransitRouteResult route) {
    final stations = <TransitStationPoint>[];
    final seen = <String>{};

    void addStation(TransitStationPoint station) {
      final key = station.id.trim().isEmpty
          ? station.name.trim().toLowerCase()
          : station.id.trim().toLowerCase();
      if (key.isNotEmpty && seen.add(key)) stations.add(station);
    }

    for (final leg in route.legs) {
      if (leg.isWalking) continue;
      addStation(
        TransitStationPoint(
          id: leg.fromStopId,
          name: leg.fromStopName,
          latitude: leg.fromLatitude,
          longitude: leg.fromLongitude,
        ),
      );
      for (final station in leg.passingStations) {
        addStation(station);
      }
      addStation(
        TransitStationPoint(
          id: leg.toStopId,
          name: leg.toStopName,
          latitude: leg.toLatitude,
          longitude: leg.toLongitude,
        ),
      );
    }
    return stations;
  }

  static TransitStationPoint? _findStopById(
    List<TransitStationPoint> stations,
    String? stopId,
  ) {
    if (stopId == null || stopId.trim().isEmpty) return null;
    final normalisedId = _normalise(stopId);
    for (final station in stations) {
      if (_normalise(station.id) == normalisedId) return station;
    }
    return null;
  }

  static TransitStationPoint? _nearestStop(
    List<TransitStationPoint> stations,
    double latitude,
    double longitude,
  ) {
    TransitStationPoint? nearest;
    var nearestDistance = double.infinity;
    for (final station in stations) {
      final latitudeDistance = latitude - station.latitude;
      final longitudeDistance = longitude - station.longitude;
      final distance =
          latitudeDistance * latitudeDistance +
          longitudeDistance * longitudeDistance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = station;
      }
    }
    return nearest;
  }
}

class _RealtimeFeedResult {
  final List<RealtimeTransitVehicle> vehicles;
  final String? error;

  const _RealtimeFeedResult({required this.vehicles, this.error});
}
