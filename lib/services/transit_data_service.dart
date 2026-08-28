import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

class NearbyTransitStop {
  final String id;
  final String name;
  final String mode;
  final double latitude;
  final double longitude;
  final double distanceMeters;

  const NearbyTransitStop({
    required this.id,
    required this.name,
    required this.mode,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });
}

class TransitPlaceSuggestion {
  final String title;
  final String subtitle;
  final String mode;

  const TransitPlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.mode,
  });
}

class TransitStationPoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  const TransitStationPoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class TransitJourneyLeg {
  final String mode;
  final String serviceName;
  final String fromStopName;
  final String toStopName;
  final String fromStopId;
  final String toStopId;
  final String departureTime;
  final String arrivalTime;
  final TransitFare? fare;
  final int durationMinutes;
  final int stopsBetween;
  final double fromLatitude;
  final double fromLongitude;
  final double toLatitude;
  final double toLongitude;
  final List<String> passingStops;
  final List<TransitStationPoint> passingStations;

  const TransitJourneyLeg({
    required this.mode,
    required this.serviceName,
    required this.fromStopName,
    required this.toStopName,
    required this.fromStopId,
    required this.toStopId,
    required this.departureTime,
    required this.arrivalTime,
    this.fare,
    required this.durationMinutes,
    required this.stopsBetween,
    required this.fromLatitude,
    required this.fromLongitude,
    required this.toLatitude,
    required this.toLongitude,
    this.passingStops = const [],
    this.passingStations = const [],
  });

  bool get isWalking => mode == 'Walk';
}

class TransitFare {
  final String adult;
  final String cash;
  final String cashless;
  final String concession;
  final bool isZoneBased;

  const TransitFare({
    required this.adult,
    required this.cash,
    required this.cashless,
    required this.concession,
    this.isZoneBased = false,
  });
}

class TransitRouteResult {
  final String fromStopName;
  final String toStopName;
  final String fromStopId;
  final String toStopId;
  final String serviceName;
  final String mode;
  final String departureTime;
  final String arrivalTime;
  final TransitFare? fare;
  final int durationMinutes;
  final int stopsBetween;
  final double fromLatitude;
  final double fromLongitude;
  final double toLatitude;
  final double toLongitude;
  final List<TransitJourneyLeg> legs;

  const TransitRouteResult({
    required this.fromStopName,
    required this.toStopName,
    required this.fromStopId,
    required this.toStopId,
    required this.serviceName,
    required this.mode,
    required this.departureTime,
    required this.arrivalTime,
    this.fare,
    required this.durationMinutes,
    required this.stopsBetween,
    required this.fromLatitude,
    required this.fromLongitude,
    required this.toLatitude,
    required this.toLongitude,
    this.legs = const [],
  });

  TransitRouteResult copyWith({TransitFare? fare}) {
    return TransitRouteResult(
      fromStopName: fromStopName,
      toStopName: toStopName,
      fromStopId: fromStopId,
      toStopId: toStopId,
      serviceName: serviceName,
      mode: mode,
      departureTime: departureTime,
      arrivalTime: arrivalTime,
      fare: fare ?? this.fare,
      durationMinutes: durationMinutes,
      stopsBetween: stopsBetween,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      legs: legs,
    );
  }
}

class TransitDataException implements Exception {
  final String message;

  const TransitDataException(this.message);

  @override
  String toString() => message;
}

class TransitDataService {
  static final _railEndpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-static/prasarana/?category=rapid-rail-kl',
  );
  static final _busEndpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-static/prasarana/?category=rapid-bus-kl',
  );
  static final _fareEndpoint = Uri.parse(
    'https://jp-web.myrapid.com.my/endpoint/geoservice/fares',
  );
  static final _geocodeEndpoint = Uri.parse(
    'https://jp-web.myrapid.com.my/endpoint/geoservice/geocode',
  );
  static const _busFareFallback = TransitFare(
    adult: '1.00',
    cash: '1.00',
    cashless: '1.00',
    concession: '0.50',
    isZoneBased: true,
  );

  final http.Client _client;
  _GtfsFeed? _railFeed;
  _GtfsFeed? _busFeed;
  Future<_GtfsFeed>? _railLoading;
  Future<_GtfsFeed>? _busLoading;
  final Map<String, Future<TransitFare?>> _fareLoading = {};

  TransitDataService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() => _client.close();

  Future<List<TransitRouteResult>> findRoutes({
    required String from,
    required String to,
    int? departureAfterSeconds,
    int? departureBeforeSeconds,
  }) async {
    final results = <TransitRouteResult>[];
    Object? firstError;
    final feeds = <_FeedSource>[];

    try {
      feeds.add(_FeedSource(await _loadRailFeed(), fallbackMode: 'LRT'));
    } catch (error) {
      firstError = error;
    }

    try {
      feeds.add(_FeedSource(await _loadBusFeed(), fallbackMode: 'Bus'));
    } catch (error) {
      firstError ??= error;
    }

    for (final source in feeds) {
      results.addAll(
        _findInFeed(
          source.feed,
          from: from,
          to: to,
          fallbackMode: source.fallbackMode,
          departureAfterSeconds: departureAfterSeconds,
          departureBeforeSeconds: departureBeforeSeconds,
        ),
      );
    }

    // A typed value is often an area, mall, or landmark rather than an
    // exact GTFS stop name. Resolve it through the official MyRapid planner,
    // then search the nearest stops in both the bus and rail feeds.
    if (results.isEmpty && feeds.isNotEmpty) {
      final originStops = await _resolveStopCandidates(from, feeds);
      final destinationStops = await _resolveStopCandidates(to, feeds);
      for (final source in feeds) {
        for (final origin in originStops.take(6)) {
          for (final destination in destinationStops.take(6)) {
            results.addAll(
              _findInFeed(
                source.feed,
                from: origin.name,
                to: destination.name,
                fallbackMode: source.fallbackMode,
                departureAfterSeconds: departureAfterSeconds,
                departureBeforeSeconds: departureBeforeSeconds,
              ),
            );
          }
        }
      }

      if (results.isEmpty) {
        results.addAll(
          await _findMultimodalRoutes(
            from: from,
            to: to,
            feeds: feeds,
            originStops: originStops,
            destinationStops: destinationStops,
            departureAfterSeconds: departureAfterSeconds,
            departureBeforeSeconds: departureBeforeSeconds,
          ),
        );
      }
    }

    if (results.isEmpty && firstError != null) {
      throw TransitDataException(
        'Government transit data is unavailable right now. Please try again.',
      );
    }

    final uniqueResults = <String, TransitRouteResult>{};
    for (final result in results) {
      final key = [
        result.serviceName,
        result.fromStopName,
        result.toStopName,
        result.departureTime,
        result.arrivalTime,
      ].join('|');
      uniqueResults.putIfAbsent(key, () => result);
    }
    final sortedResults = uniqueResults.values.toList()
      ..sort((left, right) {
        final departure = _gtfsSeconds(
          left.departureTime,
        ).compareTo(_gtfsSeconds(right.departureTime));
        if (departure != 0) return departure;
        final service = left.serviceName.compareTo(right.serviceName);
        if (service != 0) return service;
        return left.durationMinutes.compareTo(right.durationMinutes);
      });

    final resultsWithFares = <TransitRouteResult>[];
    for (final result in sortedResults) {
      final fare = result.legs.length > 1
          ? await _loadJourneyFare(result.legs)
          : await _loadFare(
              fromStopId: result.fromStopId,
              toStopId: result.toStopId,
            );
      resultsWithFares.add(
        result.copyWith(
          fare: fare ?? (result.mode == 'Bus' ? _busFareFallback : result.fare),
        ),
      );
    }
    return resultsWithFares;
  }

  Future<TransitRouteResult?> findRoute({
    required String from,
    required String to,
    int? departureAfterSeconds,
    int? departureBeforeSeconds,
  }) async {
    final routes = await findRoutes(
      from: from,
      to: to,
      departureAfterSeconds: departureAfterSeconds,
      departureBeforeSeconds: departureBeforeSeconds,
    );
    return routes.isEmpty ? null : routes.first;
  }

  Future<List<NearbyTransitStop>> findNearbyStops({
    required double latitude,
    required double longitude,
    double maxDistanceMeters = 1500,
    int limit = 8,
  }) async {
    final feeds = <_GtfsFeed>[];
    Object? firstError;

    try {
      feeds.add(await _loadRailFeed());
    } catch (error) {
      firstError = error;
    }
    try {
      feeds.add(await _loadBusFeed());
    } catch (error) {
      firstError ??= error;
    }

    if (feeds.isEmpty && firstError != null) {
      throw TransitDataException(
        'Government transit data is unavailable right now. Please try again.',
      );
    }

    final nearby = <NearbyTransitStop>[];
    for (final feed in feeds) {
      for (final stop in feed.stops.values) {
        final distanceMeters = _distanceMeters(
          latitude,
          longitude,
          stop.latitude,
          stop.longitude,
        );
        if (distanceMeters > maxDistanceMeters) continue;
        final modes = feed.stopModes[stop.id];
        nearby.add(
          NearbyTransitStop(
            id: stop.id,
            name: stop.name,
            mode: modes == null || modes.isEmpty
                ? 'Transit'
                : modes.join(' · '),
            latitude: stop.latitude,
            longitude: stop.longitude,
            distanceMeters: distanceMeters,
          ),
        );
      }
    }

    nearby.sort((left, right) {
      final distance = left.distanceMeters.compareTo(right.distanceMeters);
      if (distance != 0) return distance;
      return left.name.compareTo(right.name);
    });

    final uniqueStops = <String, NearbyTransitStop>{};
    for (final stop in nearby) {
      uniqueStops.putIfAbsent('${stop.mode}|${stop.name}', () => stop);
    }
    return uniqueStops.values.take(limit).toList();
  }

  Future<List<NearbyTransitStop>> findStopsForPlace({
    required String query,
    double maxDistanceMeters = 2500,
    int limit = 8,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return const [];

    final places = await _geocodePlace(trimmedQuery);
    if (places.isEmpty) return const [];

    final nearby = <NearbyTransitStop>[];
    for (final place in places.take(6)) {
      nearby.addAll(
        await findNearbyStops(
          latitude: place.latitude,
          longitude: place.longitude,
          maxDistanceMeters: maxDistanceMeters,
          limit: limit,
        ),
      );
    }

    nearby.sort((left, right) {
      final distance = left.distanceMeters.compareTo(right.distanceMeters);
      if (distance != 0) return distance;
      return left.name.compareTo(right.name);
    });
    final uniqueStops = <String, NearbyTransitStop>{};
    for (final stop in nearby) {
      uniqueStops.putIfAbsent('${stop.mode}|${stop.id}', () => stop);
    }
    return uniqueStops.values.take(limit).toList();
  }

  Future<List<NearbyTransitStop>> _resolveStopCandidates(
    String query,
    List<_FeedSource> feeds,
  ) async {
    final candidates = <NearbyTransitStop>[];
    final seen = <String>{};

    void addCandidate(NearbyTransitStop candidate) {
      final key = '${candidate.mode}|${candidate.id}';
      if (seen.add(key)) candidates.add(candidate);
    }

    for (final source in feeds) {
      for (final stop in _findStopCandidates(source.feed, query).take(4)) {
        final modes = source.feed.stopModes[stop.id];
        addCandidate(
          NearbyTransitStop(
            id: stop.id,
            name: stop.name,
            mode: modes == null || modes.isEmpty
                ? source.fallbackMode
                : modes.join(' · '),
            latitude: stop.latitude,
            longitude: stop.longitude,
            distanceMeters: 0,
          ),
        );
      }
    }

    for (final stop in await findStopsForPlace(
      query: query,
      maxDistanceMeters: 1800,
      limit: 10,
    )) {
      addCandidate(stop);
    }

    candidates.sort((left, right) {
      final distance = left.distanceMeters.compareTo(right.distanceMeters);
      if (distance != 0) return distance;
      return left.name.compareTo(right.name);
    });
    return candidates.take(8).toList();
  }

  Future<List<TransitRouteResult>> _findMultimodalRoutes({
    required String from,
    required String to,
    required List<_FeedSource> feeds,
    required List<NearbyTransitStop> originStops,
    required List<NearbyTransitStop> destinationStops,
    int? departureAfterSeconds,
    int? departureBeforeSeconds,
  }) async {
    if (originStops.isEmpty || destinationStops.isEmpty) return const [];

    final journeys = <TransitRouteResult>[];
    final journeyCombinationCounts = <String, int>{};
    const maxJourneysPerCombination = 8;
    const maxJourneys = 48;
    for (final origin in originStops.take(5)) {
      for (final destination in destinationStops.take(5)) {
        final transferPairs = _findTransferPairs(
          feeds: feeds,
          origin: origin,
          destination: destination,
        );
        for (final pair in transferPairs.take(28)) {
          final originIds = _candidateIds(pair.firstSource.feed, origin);
          if (originIds.isEmpty) continue;
          final destinationIds = _candidateIds(
            pair.secondSource.feed,
            destination,
          );
          if (destinationIds.isEmpty) continue;

          final originWalkingSeconds =
              _walkingMinutes(origin.distanceMeters) * 60;
          final firstAfter = departureAfterSeconds == null
              ? null
              : departureAfterSeconds + originWalkingSeconds;
          final firstBefore = departureBeforeSeconds == null
              ? null
              : departureBeforeSeconds + originWalkingSeconds;

          for (final originId in originIds) {
            final firstRoutes = _findInFeedByStopIds(
              pair.firstSource.feed,
              fromStopId: originId,
              toStopId: pair.firstStopId,
              fallbackMode: pair.firstSource.fallbackMode,
              departureAfterSeconds: firstAfter,
              departureBeforeSeconds: firstBefore,
            );
            for (final firstRoute in firstRoutes.take(40)) {
              final transferWalkingSeconds = math.max(
                120,
                _walkingMinutes(pair.distanceMeters) * 60,
              );
              final earliestSecondDeparture =
                  _gtfsSeconds(firstRoute.arrivalTime) + transferWalkingSeconds;

              for (final destinationId in destinationIds) {
                final secondRoutes = _findInFeedByStopIds(
                  pair.secondSource.feed,
                  fromStopId: pair.secondStopId,
                  toStopId: destinationId,
                  fallbackMode: pair.secondSource.fallbackMode,
                  departureAfterSeconds: earliestSecondDeparture,
                );
                if (secondRoutes.isEmpty) continue;
                final secondRoute = secondRoutes.first;
                final journey = _combineJourney(
                  from: from,
                  to: to,
                  origin: origin,
                  destination: destination,
                  firstRoute: firstRoute,
                  secondRoute: secondRoute,
                  transferDistanceMeters: pair.distanceMeters,
                );
                final combination = journey.serviceName;
                final combinationCount =
                    journeyCombinationCounts[combination] ?? 0;
                if (combinationCount >= maxJourneysPerCombination) continue;
                journeyCombinationCounts[combination] = combinationCount + 1;
                journeys.add(journey);
                break;
              }
              if (journeys.length >= maxJourneys) break;
            }
            if (journeys.length >= maxJourneys) break;
          }
          if (journeys.length >= maxJourneys) break;
        }
        if (journeys.length >= maxJourneys) break;
      }
      if (journeys.length >= maxJourneys) break;
    }

    final unique = <String, TransitRouteResult>{};
    for (final journey in journeys) {
      final key = [
        journey.serviceName,
        journey.fromStopName,
        journey.toStopName,
        journey.departureTime,
        journey.arrivalTime,
      ].join('|');
      unique.putIfAbsent(key, () => journey);
    }
    return unique.values.toList()..sort(
      (left, right) => _gtfsSeconds(
        left.departureTime,
      ).compareTo(_gtfsSeconds(right.departureTime)),
    );
  }

  List<_TransferPair> _findTransferPairs({
    required List<_FeedSource> feeds,
    required NearbyTransitStop origin,
    required NearbyTransitStop destination,
  }) {
    final pairs = <String, _TransferPair>{};
    for (final firstSource in feeds) {
      for (final originId in _candidateIds(firstSource.feed, origin)) {
        final reachable = _reachableStopIds(
          firstSource.feed,
          fromStopId: originId,
          forward: true,
        );
        if (reachable.isEmpty) continue;

        for (final secondSource in feeds) {
          for (final destinationId in _candidateIds(
            secondSource.feed,
            destination,
          )) {
            final backwards = _reachableStopIds(
              secondSource.feed,
              fromStopId: destinationId,
              forward: false,
            );
            if (backwards.isEmpty) continue;

            for (final firstStopId in reachable) {
              final firstStop = firstSource.feed.stops[firstStopId];
              if (firstStop == null) continue;
              if (firstSource == secondSource) {
                if (!backwards.contains(firstStopId)) continue;
                final key =
                    '${firstSource.fallbackMode}|$firstStopId|${secondSource.fallbackMode}|$firstStopId';
                pairs.putIfAbsent(
                  key,
                  () => _TransferPair(
                    firstSource: firstSource,
                    firstStopId: firstStopId,
                    secondSource: secondSource,
                    secondStopId: firstStopId,
                    distanceMeters: 0,
                  ),
                );
                continue;
              }

              for (final secondStopId in backwards) {
                final secondStop = secondSource.feed.stops[secondStopId];
                if (secondStop == null) continue;
                final distanceMeters = _distanceMeters(
                  firstStop.latitude,
                  firstStop.longitude,
                  secondStop.latitude,
                  secondStop.longitude,
                );
                if (distanceMeters > 650) continue;
                final key =
                    '${firstSource.fallbackMode}|$firstStopId|${secondSource.fallbackMode}|$secondStopId';
                pairs.putIfAbsent(
                  key,
                  () => _TransferPair(
                    firstSource: firstSource,
                    firstStopId: firstStopId,
                    secondSource: secondSource,
                    secondStopId: secondStopId,
                    distanceMeters: distanceMeters,
                  ),
                );
              }
            }
          }
        }
      }
    }

    final sortedPairs = pairs.values.toList()
      ..sort((left, right) {
        final leftModeChange =
            left.firstSource.fallbackMode == left.secondSource.fallbackMode
            ? 1
            : 0;
        final rightModeChange =
            right.firstSource.fallbackMode == right.secondSource.fallbackMode
            ? 1
            : 0;
        final mode = leftModeChange.compareTo(rightModeChange);
        if (mode != 0) return mode;
        return left.distanceMeters.compareTo(right.distanceMeters);
      });
    return sortedPairs;
  }

  List<String> _candidateIds(_GtfsFeed feed, NearbyTransitStop candidate) {
    if (feed.stops.containsKey(candidate.id)) return [candidate.id];
    return _findStopCandidates(
      feed,
      candidate.name,
    ).map((stop) => stop.id).toList();
  }

  TransitRouteResult _combineJourney({
    required String from,
    required String to,
    required NearbyTransitStop origin,
    required NearbyTransitStop destination,
    required TransitRouteResult firstRoute,
    required TransitRouteResult secondRoute,
    required double transferDistanceMeters,
  }) {
    final originWalkingMinutes = _walkingMinutes(origin.distanceMeters);
    final destinationWalkingMinutes = _walkingMinutes(
      destination.distanceMeters,
    );
    final firstTransitLeg = _transitLeg(firstRoute);
    final secondTransitLeg = _transitLeg(secondRoute);
    final legs = <TransitJourneyLeg>[];

    if (originWalkingMinutes > 0) {
      legs.add(
        _walkingLeg(
          fromName: from.trim(),
          toName: firstTransitLeg.fromStopName,
          departureSeconds: math.max(
            0,
            _gtfsSeconds(firstTransitLeg.departureTime) -
                originWalkingMinutes * 60,
          ),
          durationMinutes: originWalkingMinutes,
          fromLatitude: origin.latitude,
          fromLongitude: origin.longitude,
          toLatitude: firstTransitLeg.fromLatitude,
          toLongitude: firstTransitLeg.fromLongitude,
        ),
      );
    }
    legs.add(firstTransitLeg);

    if (transferDistanceMeters > 40) {
      legs.add(
        _walkingLeg(
          fromName: firstTransitLeg.toStopName,
          toName: secondTransitLeg.fromStopName,
          departureSeconds: _gtfsSeconds(firstTransitLeg.arrivalTime),
          durationMinutes: _walkingMinutes(transferDistanceMeters),
          fromLatitude: firstTransitLeg.toLatitude,
          fromLongitude: firstTransitLeg.toLongitude,
          toLatitude: secondTransitLeg.fromLatitude,
          toLongitude: secondTransitLeg.fromLongitude,
        ),
      );
    }
    legs.add(secondTransitLeg);

    if (destinationWalkingMinutes > 0) {
      legs.add(
        _walkingLeg(
          fromName: secondTransitLeg.toStopName,
          toName: to.trim(),
          departureSeconds: _gtfsSeconds(secondTransitLeg.arrivalTime),
          durationMinutes: destinationWalkingMinutes,
          fromLatitude: secondTransitLeg.toLatitude,
          fromLongitude: secondTransitLeg.toLongitude,
          toLatitude: destination.latitude,
          toLongitude: destination.longitude,
        ),
      );
    }

    final transitModes = <String>[];
    for (final leg in legs.where((leg) => !leg.isWalking)) {
      transitModes.add(leg.mode);
    }
    final distinctTransitModes = transitModes.toSet();
    final mode = distinctTransitModes.length > 1 ? 'Mixed' : transitModes.first;
    final serviceName = transitModes.join(' + ');
    final departureTime = legs.first.departureTime;
    final arrivalTime = legs.last.arrivalTime;

    return TransitRouteResult(
      fromStopName: firstTransitLeg.fromStopName,
      toStopName: secondTransitLeg.toStopName,
      fromStopId: firstTransitLeg.fromStopId,
      toStopId: secondTransitLeg.toStopId,
      serviceName: serviceName,
      mode: mode,
      departureTime: departureTime,
      arrivalTime: arrivalTime,
      fare: null,
      durationMinutes: _minutesBetween(departureTime, arrivalTime),
      stopsBetween: legs.fold<int>(
        0,
        (total, leg) => total + (leg.isWalking ? 0 : leg.stopsBetween),
      ),
      fromLatitude: firstTransitLeg.fromLatitude,
      fromLongitude: firstTransitLeg.fromLongitude,
      toLatitude: secondTransitLeg.toLatitude,
      toLongitude: secondTransitLeg.toLongitude,
      legs: legs,
    );
  }

  TransitJourneyLeg _transitLeg(TransitRouteResult route) {
    if (route.legs.length == 1 && !route.legs.first.isWalking) {
      return route.legs.first;
    }
    return TransitJourneyLeg(
      mode: route.mode,
      serviceName: route.serviceName,
      fromStopName: route.fromStopName,
      toStopName: route.toStopName,
      fromStopId: route.fromStopId,
      toStopId: route.toStopId,
      departureTime: route.departureTime,
      arrivalTime: route.arrivalTime,
      fare: route.fare,
      durationMinutes: route.durationMinutes,
      stopsBetween: route.stopsBetween,
      fromLatitude: route.fromLatitude,
      fromLongitude: route.fromLongitude,
      toLatitude: route.toLatitude,
      toLongitude: route.toLongitude,
    );
  }

  TransitJourneyLeg _walkingLeg({
    required String fromName,
    required String toName,
    required int departureSeconds,
    required int durationMinutes,
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    return TransitJourneyLeg(
      mode: 'Walk',
      serviceName: 'Walking',
      fromStopName: fromName,
      toStopName: toName,
      fromStopId: '',
      toStopId: '',
      departureTime: _formatGtfsTime(departureSeconds),
      arrivalTime: _formatGtfsTime(departureSeconds + durationMinutes * 60),
      durationMinutes: durationMinutes,
      stopsBetween: 0,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
    );
  }

  static int _walkingMinutes(double distanceMeters) {
    if (distanceMeters <= 40) return 0;
    return math.max(1, (distanceMeters / 80).ceil());
  }

  Future<List<TransitPlaceSuggestion>> searchPlaceSuggestions({
    required String query,
    int limit = 8,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 2) return const [];

    final suggestions = <TransitPlaceSuggestion>[];
    final seenTitles = <String>{};

    void addSuggestion(TransitPlaceSuggestion suggestion) {
      final key = _normalise(suggestion.title);
      if (key.isEmpty || !seenTitles.add(key)) return;
      suggestions.add(suggestion);
    }

    for (final source in [
      if (_railFeed != null) _FeedSource(_railFeed!, fallbackMode: 'LRT'),
      if (_busFeed != null) _FeedSource(_busFeed!, fallbackMode: 'Bus'),
    ]) {
      for (final stop in _findStopCandidates(source.feed, trimmedQuery)) {
        final modes = source.feed.stopModes[stop.id];
        addSuggestion(
          TransitPlaceSuggestion(
            title: stop.name,
            subtitle: 'Station or stop',
            mode: modes == null || modes.isEmpty
                ? source.fallbackMode
                : modes.join(' · '),
          ),
        );
      }
    }

    for (final place in (await _geocodePlace(trimmedQuery)).take(limit)) {
      addSuggestion(
        TransitPlaceSuggestion(
          title: place.name,
          subtitle: 'Place · nearest transit stop will be used',
          mode: 'Place',
        ),
      );
    }
    return suggestions.take(limit).toList();
  }

  Future<List<_GeocodedPlace>> _geocodePlace(String query) async {
    try {
      final endpoint = _geocodeEndpoint.replace(
        queryParameters: {
          'scope': 'WMcentral',
          'agency': 'rapidkl',
          'input': query,
        },
      );
      final response = await _client
          .get(
            endpoint,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'MyTransitAssist/1.0',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return const [];
      final rawResults = payload['results'];
      if (rawResults is! List) return const [];

      final places = <_GeocodedPlace>[];
      for (final rawResult in rawResults) {
        if (rawResult is! Map<String, dynamic>) continue;
        final rawGeometry = rawResult['geometry'];
        if (rawGeometry is! Map<String, dynamic>) continue;
        final rawCoordinates = rawGeometry['coordinates'];
        if (rawCoordinates is! List || rawCoordinates.length < 2) continue;
        final longitude = (rawCoordinates[0] as num?)?.toDouble();
        final latitude = (rawCoordinates[1] as num?)?.toDouble();
        if (latitude == null || longitude == null) continue;
        places.add(
          _GeocodedPlace(
            name: rawResult['poiname']?.toString() ?? query,
            latitude: latitude,
            longitude: longitude,
          ),
        );
      }
      return places;
    } catch (_) {
      return const [];
    }
  }

  Future<_GtfsFeed> _loadRailFeed() {
    return _railFeed != null
        ? Future.value(_railFeed!)
        : (_railLoading ??= _downloadFeed(_railEndpoint, fallbackMode: 'LRT')
              .then((feed) {
                _railFeed = feed;
                return feed;
              }));
  }

  Future<_GtfsFeed> _loadBusFeed() {
    return _busFeed != null
        ? Future.value(_busFeed!)
        : (_busLoading ??= _downloadFeed(_busEndpoint, fallbackMode: 'Bus')
              .then((feed) {
                _busFeed = feed;
                return feed;
              }));
  }

  Future<_GtfsFeed> _downloadFeed(
    Uri endpoint, {
    required String fallbackMode,
  }) async {
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
      if (!_requiredFiles.contains(fileName) && fileName != 'frequencies.txt') {
        continue;
      }
      final bytes = file.content as List<int>;
      files[fileName] = utf8.decode(bytes, allowMalformed: true);
    }
    if (!_requiredFiles.every(files.containsKey)) {
      throw const TransitDataException(
        'The government transit feed is missing timetable files.',
      );
    }
    return _GtfsFeed.fromFiles(files, fallbackMode: fallbackMode);
  }

  Future<TransitFare?> _loadFare({
    required String fromStopId,
    required String toStopId,
  }) {
    final key = '$fromStopId|$toStopId';
    return _fareLoading[key] ??= _requestFare(
      fromStopId: fromStopId,
      toStopId: toStopId,
    );
  }

  Future<TransitFare?> _requestFare({
    required String fromStopId,
    required String toStopId,
  }) async {
    // The public fare endpoint supports rail station IDs. Rapid KL bus
    // fares are zone-based and the bus GTFS feed does not publish zone IDs.
    if (int.tryParse(fromStopId) != null && int.tryParse(toStopId) != null) {
      return null;
    }
    try {
      final endpoint = _fareEndpoint.replace(
        queryParameters: {
          'agency': 'rapidkl',
          'from': fromStopId,
          'to': toStopId,
        },
      );
      final response = await _client
          .get(
            endpoint,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'MyTransitAssist/1.0',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return null;
      final fareData = payload['fares'];
      if (fareData is! Map<String, dynamic>) return null;
      final adult = fareData['adult']?.toString();
      final cash = fareData['cash']?.toString();
      final cashless = fareData['cashless']?.toString();
      final concession = fareData['consession']?.toString();
      if (adult == null || cash == null || cashless == null) return null;
      return TransitFare(
        adult: adult,
        cash: cash,
        cashless: cashless,
        concession: concession ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<TransitFare?> _loadJourneyFare(List<TransitJourneyLeg> legs) async {
    var adult = 0.0;
    var cash = 0.0;
    var cashless = 0.0;
    var concession = 0.0;
    var hasFare = false;
    var isZoneBased = false;

    for (final leg in legs.where((leg) => !leg.isWalking)) {
      final fare = await _loadFare(
        fromStopId: leg.fromStopId,
        toStopId: leg.toStopId,
      );
      final resolvedFare =
          fare ?? (leg.mode == 'Bus' ? _busFareFallback : null);
      if (resolvedFare == null) continue;
      adult += _parseFareAmount(resolvedFare.adult);
      cash += _parseFareAmount(resolvedFare.cash);
      cashless += _parseFareAmount(resolvedFare.cashless);
      concession += _parseFareAmount(resolvedFare.concession);
      hasFare = true;
      isZoneBased = isZoneBased || resolvedFare.isZoneBased;
    }
    if (!hasFare) return null;
    return TransitFare(
      adult: _formatFareAmount(adult),
      cash: _formatFareAmount(cash),
      cashless: _formatFareAmount(cashless),
      concession: _formatFareAmount(concession),
      isZoneBased: isZoneBased,
    );
  }

  static double _parseFareAmount(String value) {
    return double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
  }

  static String _formatFareAmount(double value) => value.toStringAsFixed(2);

  List<TransitRouteResult> _findInFeed(
    _GtfsFeed feed, {
    required String from,
    required String to,
    required String fallbackMode,
    int? departureAfterSeconds,
    int? departureBeforeSeconds,
  }) {
    final originCandidates = _findStopCandidates(feed, from);
    final destinationCandidates = _findStopCandidates(feed, to);
    if (originCandidates.isEmpty || destinationCandidates.isEmpty) {
      return const [];
    }

    final originIds = originCandidates.map((stop) => stop.id).toSet();
    final destinationIds = destinationCandidates.map((stop) => stop.id).toSet();
    final matches = <_TripMatch>[];

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
      final tripStartSeconds = _gtfsSeconds(stopTimes.first.arrivalTime);

      void addMatch({
        required String departureTime,
        required String arrivalTime,
      }) {
        final departureSeconds = _gtfsSeconds(departureTime);
        if (departureAfterSeconds != null &&
            departureSeconds < departureAfterSeconds) {
          return;
        }
        if (departureBeforeSeconds != null &&
            departureSeconds > departureBeforeSeconds) {
          return;
        }
        matches.add(
          _TripMatch(
            tripId: entry.key,
            originId: originTime.stopId,
            destinationId: destinationTime.stopId,
            originIndex: originIndex,
            destinationIndex: destinationIndex,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            durationMinutes: _minutesBetween(departureTime, arrivalTime),
          ),
        );
      }

      final frequencies = feed.tripFrequencies[entry.key];
      if (frequencies == null || frequencies.isEmpty) {
        addMatch(
          departureTime: originTime.departureTime,
          arrivalTime: destinationTime.arrivalTime,
        );
      } else {
        for (final frequency in frequencies) {
          for (
            var frequencyStart = frequency.startTimeSeconds;
            frequencyStart < frequency.endTimeSeconds;
            frequencyStart += frequency.headwaySeconds
          ) {
            addMatch(
              departureTime: _formatGtfsTime(
                frequencyStart +
                    _gtfsSeconds(originTime.departureTime) -
                    tripStartSeconds,
              ),
              arrivalTime: _formatGtfsTime(
                frequencyStart +
                    _gtfsSeconds(destinationTime.arrivalTime) -
                    tripStartSeconds,
              ),
            );
          }
        }
      }
    }

    matches.sort((left, right) {
      final departure = _gtfsSeconds(
        left.departureTime,
      ).compareTo(_gtfsSeconds(right.departureTime));
      if (departure != 0) return departure;
      final stops = (left.destinationIndex - left.originIndex).compareTo(
        right.destinationIndex - right.originIndex,
      );
      if (stops != 0) return stops;
      return left.durationMinutes.compareTo(right.durationMinutes);
    });

    return _matchesToResults(feed, matches, fallbackMode: fallbackMode);
  }

  List<TransitRouteResult> _findInFeedByStopIds(
    _GtfsFeed feed, {
    required String fromStopId,
    required String toStopId,
    required String fallbackMode,
    int? departureAfterSeconds,
    int? departureBeforeSeconds,
  }) {
    final matches = <_TripMatch>[];
    final occurrences = feed.stopOccurrences[fromStopId] ?? const [];
    for (final occurrence in occurrences) {
      final destinationIndex =
          feed.tripStopIndices[occurrence.tripId]?[toStopId];
      if (destinationIndex == null || destinationIndex <= occurrence.index) {
        continue;
      }

      final stopTimes = feed.tripStops[occurrence.tripId];
      if (stopTimes == null || stopTimes.isEmpty) continue;
      final originTime = stopTimes[occurrence.index];
      final destinationTime = stopTimes[destinationIndex];
      final tripStartSeconds = _gtfsSeconds(stopTimes.first.arrivalTime);

      void addMatch({
        required String departureTime,
        required String arrivalTime,
      }) {
        final departureSeconds = _gtfsSeconds(departureTime);
        if (departureAfterSeconds != null &&
            departureSeconds < departureAfterSeconds) {
          return;
        }
        if (departureBeforeSeconds != null &&
            departureSeconds > departureBeforeSeconds) {
          return;
        }
        matches.add(
          _TripMatch(
            tripId: occurrence.tripId,
            originId: fromStopId,
            destinationId: toStopId,
            originIndex: occurrence.index,
            destinationIndex: destinationIndex,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            durationMinutes: _minutesBetween(departureTime, arrivalTime),
          ),
        );
      }

      final frequencies = feed.tripFrequencies[occurrence.tripId];
      if (frequencies == null || frequencies.isEmpty) {
        addMatch(
          departureTime: originTime.departureTime,
          arrivalTime: destinationTime.arrivalTime,
        );
      } else {
        for (final frequency in frequencies) {
          for (
            var frequencyStart = frequency.startTimeSeconds;
            frequencyStart < frequency.endTimeSeconds;
            frequencyStart += frequency.headwaySeconds
          ) {
            addMatch(
              departureTime: _formatGtfsTime(
                frequencyStart +
                    _gtfsSeconds(originTime.departureTime) -
                    tripStartSeconds,
              ),
              arrivalTime: _formatGtfsTime(
                frequencyStart +
                    _gtfsSeconds(destinationTime.arrivalTime) -
                    tripStartSeconds,
              ),
            );
          }
        }
      }
    }

    matches.sort(_compareTripMatches);
    return _matchesToResults(feed, matches, fallbackMode: fallbackMode);
  }

  List<TransitRouteResult> _matchesToResults(
    _GtfsFeed feed,
    List<_TripMatch> matches, {
    required String fallbackMode,
  }) {
    final results = <TransitRouteResult>[];
    for (final match in matches) {
      final origin = feed.stops[match.originId];
      final destination = feed.stops[match.destinationId];
      if (origin == null || destination == null) continue;
      final routeId = feed.tripRoutes[match.tripId];
      final route = routeId == null ? null : feed.routes[routeId];
      final mode = route?.mode ?? fallbackMode;
      final serviceName = route?.displayName ?? 'Government transit service';
      final passingStations = _passingStations(feed, match);
      final transitLeg = TransitJourneyLeg(
        fromStopName: origin.name,
        toStopName: destination.name,
        fromStopId: origin.id,
        toStopId: destination.id,
        serviceName: serviceName,
        mode: mode,
        departureTime: match.departureTime,
        arrivalTime: match.arrivalTime,
        durationMinutes: match.durationMinutes,
        stopsBetween: match.destinationIndex - match.originIndex,
        fromLatitude: origin.latitude,
        fromLongitude: origin.longitude,
        toLatitude: destination.latitude,
        toLongitude: destination.longitude,
        passingStops: passingStations.map((station) => station.name).toList(),
        passingStations: passingStations,
      );
      results.add(
        TransitRouteResult(
          fromStopName: origin.name,
          toStopName: destination.name,
          fromStopId: origin.id,
          toStopId: destination.id,
          serviceName: serviceName,
          mode: mode,
          departureTime: match.departureTime,
          arrivalTime: match.arrivalTime,
          fare: null,
          durationMinutes: match.durationMinutes,
          stopsBetween: match.destinationIndex - match.originIndex,
          fromLatitude: origin.latitude,
          fromLongitude: origin.longitude,
          toLatitude: destination.latitude,
          toLongitude: destination.longitude,
          legs: [transitLeg],
        ),
      );
    }
    return results;
  }

  List<TransitStationPoint> _passingStations(_GtfsFeed feed, _TripMatch match) {
    final stopTimes = feed.tripStops[match.tripId];
    if (stopTimes == null) return const [];
    return [
      for (
        var index = match.originIndex;
        index <= match.destinationIndex && index < stopTimes.length;
        index++
      )
        if (feed.stops[stopTimes[index].stopId] case final stop?)
          TransitStationPoint(
            id: stop.id,
            name: stop.name,
            latitude: stop.latitude,
            longitude: stop.longitude,
          ),
    ];
  }

  Set<String> _reachableStopIds(
    _GtfsFeed feed, {
    required String fromStopId,
    required bool forward,
  }) {
    final reachable = <String>{};
    final occurrences = feed.stopOccurrences[fromStopId] ?? const [];
    for (final occurrence in occurrences) {
      final stopTimes = feed.tripStops[occurrence.tripId];
      if (stopTimes == null) continue;
      if (forward) {
        for (
          var index = occurrence.index + 1;
          index < stopTimes.length;
          index++
        ) {
          reachable.add(stopTimes[index].stopId);
        }
      } else {
        for (var index = 0; index < occurrence.index; index++) {
          reachable.add(stopTimes[index].stopId);
        }
      }
    }
    return reachable;
  }

  static int _compareTripMatches(_TripMatch left, _TripMatch right) {
    final departure = _gtfsSeconds(
      left.departureTime,
    ).compareTo(_gtfsSeconds(right.departureTime));
    if (departure != 0) return departure;
    final stops = (left.destinationIndex - left.originIndex).compareTo(
      right.destinationIndex - right.originIndex,
    );
    if (stops != 0) return stops;
    return left.durationMinutes.compareTo(right.durationMinutes);
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

  static double _distanceMeters(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(latitudeB - latitudeA);
    final longitudeDelta = _radians(longitudeB - longitudeA);
    final a =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(_radians(latitudeA)) *
            math.cos(_radians(latitudeB)) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    final clamped = a.clamp(0.0, 1.0).toDouble();
    return earthRadiusMeters * 2 * math.asin(math.sqrt(clamped));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  static String _formatGtfsTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String formatTime(String value) {
    final parts = value.split(':');
    if (parts.length != 3) return value;
    final totalHours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    if (minutes < 0 || minutes > 59) return value;
    final hour = totalHours % 24;
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour >= 12 ? 'PM' : 'AM';
    final nextDay = totalHours >= 24 ? ' (+${totalHours ~/ 24} day)' : '';
    return '$displayHour:${minutes.toString().padLeft(2, '0')} $period$nextDay';
  }
}

const _requiredFiles = {
  'stops.txt',
  'routes.txt',
  'trips.txt',
  'stop_times.txt',
};

String _inferMode(String routeName, String fallbackMode) {
  final name = routeName.toLowerCase();
  if (name.contains('mrt')) return 'MRT';
  if (name.contains('lrt') || name.contains('monorail')) return 'LRT';
  if (name.contains('bus') || name.contains('brt')) return 'Bus';
  return fallbackMode;
}

class _FeedSource {
  final _GtfsFeed feed;
  final String fallbackMode;

  const _FeedSource(this.feed, {required this.fallbackMode});
}

class _GeocodedPlace {
  final String name;
  final double latitude;
  final double longitude;

  const _GeocodedPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class _GtfsFeed {
  final Map<String, _GtfsStop> stops;
  final Map<String, _GtfsRoute> routes;
  final Map<String, String> tripRoutes;
  final Map<String, List<_GtfsStopTime>> tripStops;
  final Map<String, List<_StopOccurrence>> stopOccurrences;
  final Map<String, Map<String, int>> tripStopIndices;
  final Map<String, Set<String>> stopModes;
  final Map<String, List<_GtfsFrequency>> tripFrequencies;

  const _GtfsFeed({
    required this.stops,
    required this.routes,
    required this.tripRoutes,
    required this.tripStops,
    required this.stopOccurrences,
    required this.tripStopIndices,
    required this.stopModes,
    required this.tripFrequencies,
  });

  factory _GtfsFeed.fromFiles(
    Map<String, String> files, {
    required String fallbackMode,
  }) {
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
        mode: _inferMode(
          '${row['route_short_name'] ?? ''} ${row['route_long_name'] ?? ''} ${row['category'] ?? ''}',
          fallbackMode,
        ),
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
      tripStops
          .putIfAbsent(tripId, () => [])
          .add(
            _GtfsStopTime(
              stopId: stopId,
              arrivalTime: arrival,
              departureTime: departure,
              sequence: sequence,
            ),
          );
    }
    for (final stopsForTrip in tripStops.values) {
      stopsForTrip.sort(
        (left, right) => left.sequence.compareTo(right.sequence),
      );
    }

    final stopOccurrences = <String, List<_StopOccurrence>>{};
    final tripStopIndices = <String, Map<String, int>>{};
    for (final entry in tripStops.entries) {
      final indices = <String, int>{};
      for (var index = 0; index < entry.value.length; index++) {
        final stopId = entry.value[index].stopId;
        indices.putIfAbsent(stopId, () => index);
        stopOccurrences
            .putIfAbsent(stopId, () => [])
            .add(_StopOccurrence(tripId: entry.key, index: index));
      }
      tripStopIndices[entry.key] = indices;
    }

    final stopModes = <String, Set<String>>{};
    for (final entry in tripStops.entries) {
      final routeId = tripRoutes[entry.key];
      final mode = routeId == null ? null : routes[routeId]?.mode;
      if (mode == null) continue;
      for (final stopTime in entry.value) {
        stopModes.putIfAbsent(stopTime.stopId, () => <String>{}).add(mode);
      }
    }

    final tripFrequencies = <String, List<_GtfsFrequency>>{};
    final frequencySource = files['frequencies.txt'];
    if (frequencySource != null) {
      for (final row in _rows(frequencySource)) {
        final tripId = row['trip_id'] ?? '';
        final startTimeSeconds = TransitDataService._gtfsSeconds(
          row['start_time'] ?? '',
        );
        final endTimeSeconds = TransitDataService._gtfsSeconds(
          row['end_time'] ?? '',
        );
        final headwaySeconds = int.tryParse(row['headway_secs'] ?? '') ?? 0;
        if (tripId.isEmpty ||
            startTimeSeconds >= endTimeSeconds ||
            headwaySeconds <= 0) {
          continue;
        }
        tripFrequencies
            .putIfAbsent(tripId, () => [])
            .add(
              _GtfsFrequency(
                startTimeSeconds: startTimeSeconds,
                endTimeSeconds: endTimeSeconds,
                headwaySeconds: headwaySeconds,
              ),
            );
      }
    }

    return _GtfsFeed(
      stops: stops,
      routes: routes,
      tripRoutes: tripRoutes,
      tripStops: tripStops,
      stopOccurrences: stopOccurrences,
      tripStopIndices: tripStopIndices,
      stopModes: stopModes,
      tripFrequencies: tripFrequencies,
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
  final String mode;

  const _GtfsRoute({required this.displayName, required this.mode});
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

class _StopOccurrence {
  final String tripId;
  final int index;

  const _StopOccurrence({required this.tripId, required this.index});
}

class _TransferPair {
  final _FeedSource firstSource;
  final String firstStopId;
  final _FeedSource secondSource;
  final String secondStopId;
  final double distanceMeters;

  const _TransferPair({
    required this.firstSource,
    required this.firstStopId,
    required this.secondSource,
    required this.secondStopId,
    required this.distanceMeters,
  });
}

class _GtfsFrequency {
  final int startTimeSeconds;
  final int endTimeSeconds;
  final int headwaySeconds;

  const _GtfsFrequency({
    required this.startTimeSeconds,
    required this.endTimeSeconds,
    required this.headwaySeconds,
  });
}

class _TripMatch {
  final String tripId;
  final String originId;
  final String destinationId;
  final int originIndex;
  final int destinationIndex;
  final String departureTime;
  final String arrivalTime;
  final int durationMinutes;

  const _TripMatch({
    required this.tripId,
    required this.originId,
    required this.destinationId,
    required this.originIndex,
    required this.destinationIndex,
    required this.departureTime,
    required this.arrivalTime,
    required this.durationMinutes,
  });
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
