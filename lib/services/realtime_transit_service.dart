import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
    Map<String, TransitStationPoint>? busStopLookup,
  }) async {
    final transitLegs = route.legs.where((leg) => !leg.isWalking).toList();
    final modes = <String>{
      for (final leg in transitLegs) leg.mode,
      if (transitLegs.isEmpty) route.mode,
    };
    final busLegs = transitLegs.where((leg) => leg.mode == 'Bus').toList();
    final routeIds = <String>{};
    final routeAliases = <String>{};
    if (mappedRouteIds != null && mappedRouteIds.isNotEmpty) {
      routeIds.addAll(mappedRouteIds.map(_normaliseRouteId));
    } else {
      if (route.mode == 'Bus' &&
          route.routeId != null &&
          route.routeId!.trim().isNotEmpty) {
        routeIds.add(_normaliseRouteId(route.routeId!));
      }
      for (final leg in busLegs) {
        if (leg.routeId != null && leg.routeId!.trim().isNotEmpty) {
          routeIds.add(_normaliseRouteId(leg.routeId!));
        }
      }
    }
    for (final leg in busLegs) {
      routeAliases.addAll(_routeAliasesForService(leg.serviceName));
    }
    if (route.mode == 'Bus') {
      routeAliases.addAll(_routeAliasesForService(route.serviceName));
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
        fetchedAt: _utcNow(),
        errorMessage: wantsRail
            ? 'Live rail positions are not currently published by the official feed.'
            : 'No live transit feed is available for this route.',
      );
    }

    final results = <_RealtimeFeedResult>[];
    var kioskResult = await _fetchKioskFeed(
      routeStations,
      routeIds,
      busStopLookup,
    );
    if (kioskResult.vehicles.isEmpty && routeIds.isNotEmpty) {
      final broadResult = await _fetchKioskFeed(
        routeStations,
        const {},
        busStopLookup,
      );
      if (broadResult.vehicles.isNotEmpty) kioskResult = broadResult;
    }
    if (kioskResult.error == null && kioskResult.vehicles.isNotEmpty) {
      results.add(kioskResult);
    } else {
      final fallbackResult = await _fetchFeed(
        _busEndpoint,
        routeStations,
        busStopLookup,
      );
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
                (!_containsRouteId(
                  routeIds,
                  routeAliases,
                  vehicle.routeId!,
                )))) {
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
      fetchedAt: _utcNow(),
      errorMessage: feedWarning,
    );
  }

  Future<_RealtimeFeedResult> _fetchKioskFeed(
    List<TransitStationPoint> routeStations,
    Set<String> routeIds,
    Map<String, TransitStationPoint>? busStopLookup,
  ) async {
    final requestedRouteIds = routeIds.isEmpty
        ? <String?>[null]
        : routeIds.toList(growable: false);
    final vehicles = <RealtimeTransitVehicle>[];
    final seenIds = <String>{};
    String? firstError;

    for (final routeId in requestedRouteIds) {
      final result = await _fetchKioskRoute(
        routeStations,
        routeId,
        busStopLookup,
      );
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
    Map<String, TransitStationPoint>? busStopLookup,
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
              'sid': 'mytransitassist-${_utcNow().microsecondsSinceEpoch}',
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
              result.complete(
                _parseKioskVehicles(event[1], routeStations, busStopLookup),
              );
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
      }
    }
  }

  List<RealtimeTransitVehicle> _parseKioskVehicles(
    dynamic encodedPayload,
    List<TransitStationPoint> routeStations,
    Map<String, TransitStationPoint>? busStopLookup,
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
      final feedStopName = _feedStopName(record);
      final catalogueStop = _lookupStop(busStopLookup, feedStopId);
      final exactStop =
          catalogueStop ?? _findStopById(routeStations, feedStopId);
      final nearestStop = exactStop == null
          ? _nearestStop(
              routeStations,
              latitude,
              longitude,
              additionalStations: busStopLookup?.values,
            )
          : null;
      final currentStop = exactStop ?? nearestStop;
      final currentStopName =
          exactStop?.name ??
          (feedStopName.isEmpty ? currentStop?.name : feedStopName);
      final id = busId.isNotEmpty
          ? busId
          : '${routeId}_${latitude.toStringAsFixed(5)}_${longitude.toStringAsFixed(5)}';
      vehicles.add(
        RealtimeTransitVehicle(
          id: id,
          mode: 'Bus',
          routeId: routeId.isEmpty ? null : routeId,
          currentStopId: feedStopId.isNotEmpty ? feedStopId : currentStop?.id,
          currentStopName: currentStopName,
          currentStopEstimated:
              exactStop == null && currentStop != null && feedStopName.isEmpty,
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
    Map<String, TransitStationPoint>? busStopLookup,
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
        final catalogueStop = _lookupStop(busStopLookup, feedStopId);
        final exactStop =
            catalogueStop ?? _findStopById(routeStations, feedStopId);
        final nearestStop = exactStop == null
            ? _nearestStop(
                routeStations,
                position.latitude,
                position.longitude,
                additionalStations: busStopLookup?.values,
              )
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
            currentStopId: feedStopId ?? currentStop?.id,
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

  static String _normaliseRouteId(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  }

  static bool _containsRouteId(
    Set<String> routeIds,
    Set<String> routeAliases,
    String routeId,
  ) {
    final normalised = _normaliseRouteId(routeId);
    return routeIds.contains(normalised) || routeAliases.contains(normalised);
  }

  static Set<String> _routeAliasesForService(String serviceName) {
    final key = _normaliseRouteId(serviceName);
    if (key.isEmpty) return const {};

    final aliases = <String>{key};
    final alphabeticRoute = RegExp(r'^([a-z]+)(\d+[a-z]*)$').firstMatch(key);
    if (alphabeticRoute != null) {
      final prefix = alphabeticRoute.group(1)!;
      final number = alphabeticRoute.group(2)!;
      aliases
        ..add('$prefix${number}0')
        ..add('$prefix${number}8');
      if (key.endsWith('0') && number.length > 3) {
        aliases.add(key.substring(0, key.length - 1));
      }
    } else if (RegExp(r'^\d+$').hasMatch(key)) {
      aliases
        ..add('u${key}0')
        ..add('u${key}8');
      if (key.endsWith('0') && key.length > 3) {
        aliases.add(key.substring(0, key.length - 1));
      }
    }
    return aliases;
  }

  static String _normaliseVehicleId(RealtimeTransitVehicle vehicle) {
    final id = vehicle.id.trim();
    return (id.isEmpty ? vehicle.label : id).trim().toLowerCase();
  }

  static String _textValue(dynamic value) => value?.toString().trim() ?? '';

  static String _feedStopName(Map<String, dynamic> record) {
    for (final key in const [
      'busstop_name',
      'stop_name',
      'current_stop_name',
      'current_stop',
    ]) {
      final value = record[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

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

  static TransitStationPoint? _lookupStop(
    Map<String, TransitStationPoint>? lookup,
    String? stopId,
  ) {
    if (lookup == null || stopId == null || stopId.trim().isEmpty) return null;
    final normalisedId = _normaliseStopId(stopId);
    return lookup[normalisedId];
  }

  static String _normaliseStopId(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static TransitStationPoint? _nearestStop(
    List<TransitStationPoint> stations,
    double latitude,
    double longitude, {
    Iterable<TransitStationPoint>? additionalStations,
  }) {
    TransitStationPoint? nearest;
    var nearestDistance = double.infinity;
    for (final station in [...stations, ...?additionalStations]) {
      final distance = _distanceMeters(
        latitude,
        longitude,
        station.latitude,
        station.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = station;
      }
    }
    return nearestDistance <= 250 ? nearest : null;
  }

  static double _distanceMeters(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDifference = _radians(latitudeB - latitudeA);
    final longitudeDifference = _radians(longitudeB - longitudeA);
    final a =
        math.sin(latitudeDifference / 2) * math.sin(latitudeDifference / 2) +
        math.cos(_radians(latitudeA)) *
            math.cos(_radians(latitudeB)) *
            math.sin(longitudeDifference / 2) *
            math.sin(longitudeDifference / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  static DateTime _utcNow() => DateTime.now().toUtc();
}

class _RealtimeFeedResult {
  final List<RealtimeTransitVehicle> vehicles;
  final String? error;

  const _RealtimeFeedResult({required this.vehicles, this.error});
}
