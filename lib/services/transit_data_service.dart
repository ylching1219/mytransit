import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

class TransitRouteResult {
  final String fromStopName;
  final String toStopName;
  final String serviceName;
  final int durationMinutes;
  final int stopsBetween;
  final double fromLatitude;
  final double fromLongitude;
  final double toLatitude;
  final double toLongitude;

  const TransitRouteResult({
    required this.fromStopName,
    required this.toStopName,
    required this.serviceName,
    required this.durationMinutes,
    required this.stopsBetween,
    required this.fromLatitude,
    required this.fromLongitude,
    required this.toLatitude,
    required this.toLongitude,
  });
}

class TransitDataException implements Exception {
  final String message;

  const TransitDataException(this.message);

  @override
  String toString() => message;
}

class TransitDataService {
  static final _railEndpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl',
  );
  static final _busEndpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl',
  );

  final http.Client _client;
  _GtfsFeed? _railFeed;
  _GtfsFeed? _busFeed;
  Future<_GtfsFeed>? _railLoading;
  Future<_GtfsFeed>? _busLoading;

  TransitDataService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() => _client.close();

  Future<TransitRouteResult?> findRoute({
    required String from,
    required String to,
  }) async {
    Object? firstError;

    try {
      final railResult = _findInFeed(
        await _loadRailFeed(),
        from: from,
        to: to,
      );
      if (railResult != null) return railResult;
    } catch (error) {
      firstError = error;
    }

    try {
      final busResult = _findInFeed(
        await _loadBusFeed(),
        from: from,
        to: to,
      );
      if (busResult != null) return busResult;
    } catch (error) {
      firstError ??= error;
    }

    if (firstError != null) {
      throw TransitDataException(
        'Government transit data is unavailable right now. Please try again.',
      );
    }
    return null;
  }

  Future<_GtfsFeed> _loadRailFeed() {
    return _railFeed != null
        ? Future.value(_railFeed!)
        : (_railLoading ??= _downloadFeed(_railEndpoint).then((feed) {
            _railFeed = feed;
            return feed;
          }));
  }

  Future<_GtfsFeed> _loadBusFeed() {
    return _busFeed != null
        ? Future.value(_busFeed!)
        : (_busLoading ??= _downloadFeed(_busEndpoint).then((feed) {
            _busFeed = feed;
            return feed;
          }));
  }

  Future<_GtfsFeed> _downloadFeed(Uri endpoint) async {
    final response = await _client
        .get(endpoint)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw TransitDataException(
        'Government transit API returned HTTP ${response.statusCode}.',
      );
    }


    final archive = ZipDecoder().decodeBytes(response.bodyBytes);
    final files = <String, String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final fileName = file.name.split(RegExp(r'[\\/]')).last.toLowerCase();
      if (!_requiredFiles.contains(fileName)) continue;
      final bytes = file.content as List<int>;
      files[fileName] = utf8.decode(bytes, allowMalformed: true);
    }
    if (!_requiredFiles.every(files.containsKey)) {
      throw const TransitDataException(
        'The government transit feed is missing timetable files.',
      );
    }
    return _GtfsFeed.fromFiles(files);
  }

  TransitRouteResult? _findInFeed(
    _GtfsFeed feed, {
    required String from,
    required String to,
  }) {
    final originQuery = _normalise(from).contains('currentlocation')
        ? 'KL Sentral'
        : from;
    final originCandidates = _findStopCandidates(feed, originQuery);
    final destinationCandidates = _findStopCandidates(feed, to);
    if (originCandidates.isEmpty || destinationCandidates.isEmpty) return null;

    final originIds = originCandidates.map((stop) => stop.id).toSet();
    final destinationIds = destinationCandidates.map((stop) => stop.id).toSet();
    _TripMatch? best;

    for (final entry in feed.tripStops.entries) {
      final stopTimes = entry.value;
      var originIndex = -1;
      var destinationIndex = -1;
      for (var index = 0; index < stopTimes.length; index++) {
        final stopId = stopTimes[index].stopId;
        if (originIndex == -1 && originIds.contains(stopId)) {
          originIndex = index;
        }
        if (originIndex != -1 &&
            index > originIndex &&
            destinationIds.contains(stopId)) {
          destinationIndex = index;
          break;
        }
      }
      if (originIndex == -1 || destinationIndex == -1) continue;

      final originTime = stopTimes[originIndex];
      final destinationTime = stopTimes[destinationIndex];
      final duration = _minutesBetween(
        originTime.departureTime,
        destinationTime.arrivalTime,
      );
      final match = _TripMatch(
        tripId: entry.key,
        originId: originTime.stopId,
        destinationId: destinationTime.stopId,
        originIndex: originIndex,
        destinationIndex: destinationIndex,
        durationMinutes: duration,
      );
      if (best == null || match.isBetterThan(best)) best = match;
    }

    if (best == null) return null;
    final origin = feed.stops[best.originId];
    final destination = feed.stops[best.destinationId];
    if (origin == null || destination == null) return null;
    final routeId = feed.tripRoutes[best.tripId];
    final route = routeId == null ? null : feed.routes[routeId];

    return TransitRouteResult(
      fromStopName: origin.name,
      toStopName: destination.name,
      serviceName: route?.displayName ?? 'Government transit service',
      durationMinutes: best.durationMinutes,
      stopsBetween: best.destinationIndex - best.originIndex,
      fromLatitude: origin.latitude,
      fromLongitude: origin.longitude,
      toLatitude: destination.latitude,
      toLongitude: destination.longitude,
    );
  }

  List<_GtfsStop> _findStopCandidates(_GtfsFeed feed, String query) {
    final normalisedQuery = _normalise(query);
    if (normalisedQuery.isEmpty) return const [];
    final scored = <_ScoredStop>[];
    for (final stop in feed.stops.values) {
      final name = _normalise(stop.name);
      if (name == normalisedQuery) {
        scored.add(_ScoredStop(stop, 0));
      } else if (name.startsWith(normalisedQuery)) {
        scored.add(_ScoredStop(stop, 1));
      } else if (name.contains(normalisedQuery)) {
        scored.add(_ScoredStop(stop, 2));
      }
    }
    scored.sort((left, right) {
      final score = left.score.compareTo(right.score);
      return score != 0 ? score : left.stop.name.compareTo(right.stop.name);
    });
    return scored.take(12).map((item) => item.stop).toList();
  }

  static String _normalise(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static int _minutesBetween(String departure, String arrival) {
    final seconds = _gtfsSeconds(arrival) - _gtfsSeconds(departure);
    if (seconds <= 0) return 1;
    final minutes = (seconds / 60).round();
    if (minutes < 1) return 1;
    if (minutes > 24 * 60) return 24 * 60;
    return minutes;
  }

  static int _gtfsSeconds(String value) {
    final parts = value.split(':');
    if (parts.length != 3) return 0;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = int.tryParse(parts[2]) ?? 0;
    return hours * 3600 + minutes * 60 + seconds;
  }
}

const _requiredFiles = {
  'stops.txt',
  'routes.txt',
  'trips.txt',
  'stop_times.txt',
};

class _GtfsFeed {
  final Map<String, _GtfsStop> stops;
  final Map<String, _GtfsRoute> routes;
  final Map<String, String> tripRoutes;
  final Map<String, List<_GtfsStopTime>> tripStops;

  const _GtfsFeed({
    required this.stops,
    required this.routes,
    required this.tripRoutes,
    required this.tripStops,
  });

  factory _GtfsFeed.fromFiles(Map<String, String> files) {
    final stops = <String, _GtfsStop>{};
    for (final row in _rows(files['stops.txt']!)) {
      final id = row['stop_id'] ?? '';
      final name = row['stop_name'] ?? '';
      final latitude = double.tryParse(row['stop_lat'] ?? '');
      final longitude = double.tryParse(row['stop_lon'] ?? '');
      if (id.isEmpty || name.isEmpty || latitude == null || longitude == null) {
        continue;
      }
      stops[id] = _GtfsStop(
        id: id,
        name: name,
        latitude: latitude,
        longitude: longitude,
      );
    }

    final routes = <String, _GtfsRoute>{};
    for (final row in _rows(files['routes.txt']!)) {
      final id = row['route_id'] ?? '';
      if (id.isEmpty) continue;
      routes[id] = _GtfsRoute(
        displayName: (row['route_long_name'] ?? '').trim().isNotEmpty
            ? row['route_long_name']!.trim()
            : (row['route_short_name'] ?? id).trim(),
      );
    }

    final tripRoutes = <String, String>{};
    for (final row in _rows(files['trips.txt']!)) {
      final tripId = row['trip_id'] ?? '';
      final routeId = row['route_id'] ?? '';
      if (tripId.isNotEmpty && routeId.isNotEmpty) {
        tripRoutes[tripId] = routeId;
      }
    }

    final tripStops = <String, List<_GtfsStopTime>>{};
    for (final row in _rows(files['stop_times.txt']!)) {
      final tripId = row['trip_id'] ?? '';
      final stopId = row['stop_id'] ?? '';
      if (tripId.isEmpty || !stops.containsKey(stopId)) continue;
      final arrival = row['arrival_time'] ?? '';
      final departure = row['departure_time'] ?? arrival;
      final sequence = int.tryParse(row['stop_sequence'] ?? '') ?? 0;
      tripStops.putIfAbsent(tripId, () => []).add(
        _GtfsStopTime(
          stopId: stopId,
          arrivalTime: arrival,
          departureTime: departure,
          sequence: sequence,
        ),
      );
    }
    for (final stopsForTrip in tripStops.values) {
      stopsForTrip.sort((left, right) => left.sequence.compareTo(right.sequence));
    }

    return _GtfsFeed(
      stops: stops,
      routes: routes,
      tripRoutes: tripRoutes,
      tripStops: tripStops,
    );
  }
}

class _GtfsStop {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  const _GtfsStop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class _GtfsRoute {
  final String displayName;

  const _GtfsRoute({required this.displayName});
}

class _GtfsStopTime {
  final String stopId;
  final String arrivalTime;
  final String departureTime;
  final int sequence;

  const _GtfsStopTime({
    required this.stopId,
    required this.arrivalTime,
    required this.departureTime,
    required this.sequence,
  });
}

class _TripMatch {
  final String tripId;
  final String originId;
  final String destinationId;
  final int originIndex;
  final int destinationIndex;
  final int durationMinutes;

  const _TripMatch({
    required this.tripId,
    required this.originId,
    required this.destinationId,
    required this.originIndex,
    required this.destinationIndex,
    required this.durationMinutes,
  });

  bool isBetterThan(_TripMatch other) {
    final thisStops = destinationIndex - originIndex;
    final otherStops = other.destinationIndex - other.originIndex;
    if (thisStops != otherStops) return thisStops < otherStops;
    return durationMinutes < other.durationMinutes;
  }
}

class _ScoredStop {
  final _GtfsStop stop;
  final int score;

  const _ScoredStop(this.stop, this.score);
}

List<Map<String, String>> _rows(String source) {
  final records = _parseCsv(source);
  if (records.isEmpty) return const [];
  final headers = records.first
      .map((header) => header.replaceFirst('\uFEFF', '').trim())
      .toList();
  return [
    for (final record in records.skip(1))
      if (record.any((value) => value.trim().isNotEmpty))
        {
          for (var index = 0; index < headers.length; index++)
            headers[index]: index < record.length ? record[index].trim() : '',
        },
  ];
}

List<List<String>> _parseCsv(String source) {
  final records = <List<String>>[];
  var record = <String>[];
  var field = StringBuffer();
  var quoted = false;

  void addField() {
    record.add(field.toString());
    field = StringBuffer();
  }

  void addRecord() {
    addField();
    records.add(record);
    record = <String>[];
  }

  for (var index = 0; index < source.length; index++) {
    final character = source[index];
    if (character == '"') {
      if (quoted && index + 1 < source.length && source[index + 1] == '"') {
        field.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      addField();
    } else if ((character == '\n' || character == '\r') && !quoted) {
      if (character == '\r' &&
          index + 1 < source.length &&
          source[index + 1] == '\n') {
        index++;
      }
      addRecord();
    } else {
      field.write(character);
    }
  }
  if (field.length > 0 || record.isNotEmpty) addRecord();
  return records;
}
