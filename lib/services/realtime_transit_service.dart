import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

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
  static final _kioskSocketEndpoint = Uri.parse(
    'wss://rapidbus-socketio-avl.prasarana.com.my/socket.io/?EIO=3&transport=websocket',
  );
  static final _busEndpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl',
  );
  final http.Client _client;

  RealtimeTransitService({http.Client? client})
    : _client = client ?? http.Client();

  Future<RealtimeTransitSnapshot> fetchForRoute(
    TransitRouteResult route, {
    Set<String>? mappedRouteIds,
  }) async {
    final transitLegs = route.legs.where((leg) => !leg.isWalking).toList();
    final modes = <String>{
      for (final leg in transitLegs) leg.mode,
      if (transitLegs.isEmpty) route.mode,
    };
    final busLegs = transitLegs.where((leg) => leg.mode == 'Bus').toList();
    final routeIds = <String>{};
    if (mappedRouteIds != null && mappedRouteIds.isNotEmpty) {
      routeIds.addAll(mappedRouteIds.map(_normalise));
    } else {
      if (route.mode == 'Bus' &&
          route.routeId != null &&
          route.routeId!.trim().isNotEmpty) {
        routeIds.add(_normalise(route.routeId!));
      }
      for (final leg in busLegs) {
        if (leg.routeId != null && leg.routeId!.trim().isNotEmpty) {
          routeIds.add(_normalise(leg.routeId!));
        }
      }
    }
    final routeStations = _stationsForRoute(route);

    final wantsBus = busLegs.isNotEmpty || route.mode == 'Bus';
    final wantsRail =
        modes.contains('LRT') ||
        modes.contains('MRT') ||
        modes.contains('Rail') ||
        modes.contains('Mixed');
    if (!wantsBus) {
      return RealtimeTransitSnapshot(
        vehicles: const [],
        fetchedAt: DateTime.now(),
        errorMessage: wantsRail
            ? 'Live rail positions are not currently published by the official feed.'
            : 'No live transit feed is available for this route.',
      );
    }

    final results = <_RealtimeFeedResult>[];
    final kioskResult = await _fetchKioskFeed(routeStations, routeIds);
    if (kioskResult.error == null) {
      results.add(kioskResult);
    } else {
      // Keep the government GTFS-realtime endpoint as a fallback if the
      // Prasarana kiosk socket is temporarily unavailable.
      final fallbackResult = await _fetchFeed(_busEndpoint, routeStations);
      results.add(
        fallbackResult.error == null || fallbackResult.vehicles.isNotEmpty
            ? fallbackResult
            : kioskResult,
      );
    }

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

  Future<_RealtimeFeedResult> _fetchKioskFeed(
    List<TransitStationPoint> routeStations,
    Set<String> routeIds,
  ) async {
    final requestedRouteIds = routeIds.isEmpty
        ? <String?>[null]
        : routeIds.toList(growable: false);
    final vehicles = <RealtimeTransitVehicle>[];
    final seenIds = <String>{};
    String? firstError;

    for (final routeId in requestedRouteIds) {
      final result = await _fetchKioskRoute(routeStations, routeId);
      firstError ??= result.error;
      for (final vehicle in result.vehicles) {
        if (seenIds.add(_normaliseVehicleId(vehicle))) {
          vehicles.add(vehicle);
        }
      }
    }

    return _RealtimeFeedResult(
      vehicles: vehicles,
      error: vehicles.isNotEmpty ? null : firstError,
    );
  }

  Future<_RealtimeFeedResult> _fetchKioskRoute(
    List<TransitStationPoint> routeStations,
    String? routeId,
  ) async {
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? subscription;
    final result = Completer<List<RealtimeTransitVehicle>>();

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (result.isCompleted) return;
      result.completeError(error, stackTrace ?? StackTrace.current);
    }

    try {
      channel = WebSocketChannel.connect(_kioskSocketEndpoint);
      await channel.ready.timeout(const Duration(seconds: 12));
      var reloadSent = false;
      subscription = channel.stream.listen(
        (message) {
          final frame = message is String
              ? message
              : utf8.decode(message as List<int>);
          if (frame.startsWith('0')) {
            channel!.sink.add('40');
            return;
          }
          if (frame.startsWith('40') && !reloadSent) {
            reloadSent = true;
            final payload = jsonEncode(<String, Object?>{
              'sid': 'mytransitassist-${DateTime.now().microsecondsSinceEpoch}',
              'uid': '',
              'provider': 'RKL',
              'route': routeId?.toUpperCase() ?? '',
            });
            channel!.sink.add('42["onFts-reload",$payload]');
            return;
          }
          if (frame == '2') {
            channel!.sink.add('3');
            return;
          }
          if (!frame.startsWith('42')) return;

          try {
            final event = jsonDecode(frame.substring(2));
            if (event is! List ||
                event.length < 2 ||
                event.first != 'onFts-client') {
              return;
            }
            if (!result.isCompleted) {
              result.complete(_parseKioskVehicles(event[1], routeStations));
            }
          } catch (error, stackTrace) {
            completeError(error, stackTrace);
          }
        },
        onError: completeError,
        onDone: () {
          if (!result.isCompleted) {
            completeError(StateError('Prasarana kiosk feed closed early.'));
          }
        },
      );
      final vehicles = await result.future.timeout(const Duration(seconds: 12));
      return _RealtimeFeedResult(vehicles: vehicles);
    } catch (_) {
      return const _RealtimeFeedResult(
        vehicles: [],
        error: 'Prasarana live bus data is temporarily unavailable.',
      );
    } finally {
      await subscription?.cancel();
      try {
        await channel?.sink.close();
      } catch (_) {
        // The socket may already be closed after the first kiosk response.
      }
    }
  }

  List<RealtimeTransitVehicle> _parseKioskVehicles(
    dynamic encodedPayload,
    List<TransitStationPoint> routeStations,
  ) {
    if (encodedPayload is! String || encodedPayload.trim().isEmpty) {
      return const [];
    }

    final compressed = base64.decode(encodedPayload);
    List<int> decompressed;
    try {
      decompressed = const ZLibDecoder().decodeBytes(compressed);
    } catch (_) {
      decompressed = const GZipDecoder().decodeBytes(compressed);
    }
    final decoded = jsonDecode(utf8.decode(decompressed));
    final records = decoded is List
        ? decoded
        : decoded is Map
        ? (decoded['data'] ?? decoded['vehicles'] ?? decoded['result'])
        : null;
    if (records is! List) return const [];

    final vehicles = <RealtimeTransitVehicle>[];
    for (final rawRecord in records) {
      if (rawRecord is! Map) continue;
      final record = rawRecord.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final latitude = _doubleValue(record['latitude'] ?? record['lat']);
      final longitude = _doubleValue(record['longitude'] ?? record['lon']);
      if (latitude == null ||
          longitude == null ||
          (latitude == 0 && longitude == 0)) {
        continue;
      }

      final routeId = _textValue(record['route'] ?? record['route_id']);
      final busId = _textValue(
        record['bus_no'] ?? record['vehicle_id'] ?? record['id'],
      );
      final feedStopId = _textValue(record['busstop_id'] ?? record['stop_id']);
      final exactStop = _findStopById(routeStations, feedStopId);
      final nearestStop = exactStop == null
          ? _nearestStop(routeStations, latitude, longitude)
          : null;
      final currentStop = exactStop ?? nearestStop;
      final id = busId.isNotEmpty
          ? busId
          : '${routeId}_${latitude.toStringAsFixed(5)}_${longitude.toStringAsFixed(5)}';
      vehicles.add(
        RealtimeTransitVehicle(
          id: id,
          mode: 'Bus',
          routeId: routeId.isEmpty ? null : routeId,
          currentStopId:
              currentStop?.id ?? (feedStopId.isEmpty ? null : feedStopId),
          currentStopName: currentStop?.name,
          currentStopEstimated: exactStop == null && currentStop != null,
          label: busId.isNotEmpty
              ? busId
              : (routeId.isEmpty ? 'Live bus' : routeId),
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }
    return vehicles;
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

  static String _normaliseVehicleId(RealtimeTransitVehicle vehicle) {
    final id = vehicle.id.trim();
    return (id.isEmpty ? vehicle.label : id).trim().toLowerCase();
  }

  static String _textValue(dynamic value) => value?.toString().trim() ?? '';

  static double? _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

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
