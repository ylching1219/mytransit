import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/realtime_transit_service.dart';
import '../services/transit_data_service.dart';
import '../widgets/smart_move_widgets.dart';
import '../widgets/transit_route_map.dart';

class LiveTrackingPage extends StatefulWidget {
  final TransitRouteResult route;

  const LiveTrackingPage({required this.route, super.key});

  @override
  State<LiveTrackingPage> createState() => _LiveTrackingPageState();
}

class _LiveTrackingPageState extends State<LiveTrackingPage>
    with WidgetsBindingObserver {
  Future<void> _markJourneyDone() async {
    final saved = await context.read<AppState>().markNextJourneyDone();
    if (!mounted || !saved) return;
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().startJourneyMonitoring();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Android may pause timers while the app is backgrounded. Refresh as soon
    // as the live page becomes visible again and restart monitoring if needed.
    unawaited(context.read<AppState>().startJourneyMonitoring());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final route = state.nextRoute ?? widget.route;
    final stations = _stationsForRoute(route);
    final stationGroups = _stationGroupsForRoute(route);
    final reportedStopName = _reportedLiveStopName(
      stations,
      state.liveTransitVehicles,
    );
    final remaining = state.journeyRemainingStations;
    final reachedIndex = _reachedIndex(
      stationCount: stations.length,
      remaining: remaining,
      arrived: state.journeyArrived,
    );
    final latestLocation = state.locationHistory.isEmpty
        ? null
        : state.locationHistory.first;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(7, 0, 7, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(
                title: 'Live tracking',
                avatarLabel: avatarInitials(state.profileName),
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: theme.colorScheme.onSurface,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: PageTitle(
                      kicker: 'LIVE JOURNEY',
                      title: state.journeyArrived
                          ? 'You have arrived'
                          : 'Track your journey',
                      trailing: _TrackingStatusPill(
                        active: state.journeyMonitoring,
                        arrived: state.journeyArrived,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              SoftCard(
                color: appCardColor(context, kPurpleSoft),
                padding: const EdgeInsets.fromLTRB(12, 11, 11, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _modeIcon(route.mode),
                          color: _modeColor(route.mode),
                          size: 21,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            route.serviceName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ).copyWith(color: theme.colorScheme.onSurface),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${route.fromStopName} → ${route.toStopName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ).copyWith(color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TrackingStat(
                            label: 'DEPART',
                            value: TransitDataService.formatTime(
                              route.departureTime,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _TrackingStat(
                            label: 'ARRIVE',
                            value: TransitDataService.formatTime(
                              route.arrivalTime,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _TrackingStat(
                            label: 'STOPS LEFT',
                            value: remaining == null ? '—' : '$remaining',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _TrackingStatusCard(
                monitoring: state.journeyMonitoring,
                arrived: state.journeyArrived,
                remaining: remaining,
                hasLocation: state.journeyHasLocation,
              ),
              if (_hasBusLeg(route)) ...[
                const SizedBox(height: 10),
                _BusAssignmentCard(
                  bus: state.assignedBus,
                  status: state.busDetectionStatus,
                ),
              ],
              const SizedBox(height: 10),
              _TransitLiveFeedCard(
                vehicles: state.liveTransitVehicles,
                assignedBus: state.assignedBus,
                updatedAt: state.liveTransitUpdatedAt,
                loading: state.liveTransitLoading,
                errorMessage: state.liveTransitError,
                reportedStopName: reportedStopName,
                onRefresh: state.refreshLiveTransitData,
              ),
              const SizedBox(height: 14),
              const SectionHeading(title: 'Live map'),
              const SizedBox(height: 8),
              TransitRouteMap(
                route: route,
                currentLocation:
                    latestLocation == null ||
                        latestLocation.latitude == null ||
                        latestLocation.longitude == null
                    ? null
                    : LatLng(
                        latestLocation.latitude!,
                        latestLocation.longitude!,
                      ),
                liveVehicles: state.liveTransitVehicles,
              ),
              const SizedBox(height: 14),
              SectionHeading(
                title: 'Stations on this journey',
                trailing: '${stations.length} stops',
              ),
              const SizedBox(height: 8),
              ..._stationGroupWidgets(
                context,
                stationGroups,
                stations,
                reachedIndex,
              ),
              const SizedBox(height: 14),
              if (state.journeyArrived)
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: _markJourneyDone,
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text(
                      'Mark journey as done',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: kTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: state.journeyMonitoring
                      ? OutlinedButton.icon(
                          onPressed: state.stopJourneyMonitoring,
                          icon: const Icon(Icons.pause_rounded, size: 17),
                          label: const Text(
                            'Pause live tracking',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kPurple,
                            side: const BorderSide(color: kPurple),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: state.startJourneyMonitoring,
                          icon: const Icon(Icons.play_arrow_rounded, size: 17),
                          label: const Text(
                            'Start live tracking',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: kTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text(
                      'Mark journey as done after arrival',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      disabledForegroundColor: theme
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: .65),
                      side: BorderSide(color: appFieldBorder(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    state.journeyMonitoring
                        ? 'Keep location and journey notifications enabled for station alerts.'
                        : 'Start tracking again when you are ready to continue.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 8.5, color: kMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int _reachedIndex({
    required int stationCount,
    required int? remaining,
    required bool arrived,
  }) {
    if (stationCount == 0 || remaining == null) return -1;
    if (arrived) return stationCount - 1;
    return (stationCount - remaining - 1).clamp(-1, stationCount - 1);
  }

  List<TransitStationPoint> _stationsForRoute(TransitRouteResult route) {
    final stations = <TransitStationPoint>[];
    final seen = <String>{};
    for (final leg in route.legs) {
      if (leg.isWalking) continue;
      for (final station in leg.passingStations) {
        if (seen.add(station.name.toLowerCase().trim())) {
          stations.add(station);
        }
      }
    }
    if (stations.isNotEmpty) return stations;
    return [
      TransitStationPoint(
        id: route.fromStopId,
        name: route.fromStopName,
        latitude: route.fromLatitude,
        longitude: route.fromLongitude,
      ),
      TransitStationPoint(
        id: route.toStopId,
        name: route.toStopName,
        latitude: route.toLatitude,
        longitude: route.toLongitude,
      ),
    ];
  }

  List<_StationServiceGroup> _stationGroupsForRoute(TransitRouteResult route) {
    final groups = <_StationServiceGroup>[];
    final transitLegs = route.legs.where((leg) => !leg.isWalking).toList();
    for (final leg in transitLegs) {
      final legStations = leg.passingStations.isNotEmpty
          ? leg.passingStations
          : [
              TransitStationPoint(
                id: leg.fromStopId,
                name: leg.fromStopName,
                latitude: leg.fromLatitude,
                longitude: leg.fromLongitude,
              ),
              TransitStationPoint(
                id: leg.toStopId,
                name: leg.toStopName,
                latitude: leg.toLatitude,
                longitude: leg.toLongitude,
              ),
            ];
      final serviceName = leg.serviceName.trim().isEmpty
          ? leg.mode
          : leg.serviceName;
      final isSameService =
          groups.isNotEmpty &&
          groups.last.mode == leg.mode &&
          groups.last.serviceName == serviceName;
      if (isSameService) {
        groups[groups.length - 1] = _StationServiceGroup(
          mode: groups.last.mode,
          serviceName: groups.last.serviceName,
          stations: _uniqueStations([...groups.last.stations, ...legStations]),
        );
      } else {
        groups.add(
          _StationServiceGroup(
            mode: leg.mode,
            serviceName: serviceName,
            stations: _uniqueStations(legStations),
          ),
        );
      }
    }
    if (groups.isEmpty) {
      groups.add(
        _StationServiceGroup(
          mode: route.mode,
          serviceName: route.serviceName,
          stations: _uniqueStations(_stationsForRoute(route)),
        ),
      );
    }
    return groups;
  }

  List<TransitStationPoint> _uniqueStations(
    Iterable<TransitStationPoint> stations,
  ) {
    final unique = <TransitStationPoint>[];
    final seen = <String>{};
    for (final station in stations) {
      final key = station.name.trim().toLowerCase();
      if (key.isNotEmpty && seen.add(key)) unique.add(station);
    }
    return unique;
  }

  List<Widget> _stationGroupWidgets(
    BuildContext context,
    List<_StationServiceGroup> groups,
    List<TransitStationPoint> allStations,
    int reachedIndex,
  ) {
    final widgets = <Widget>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final group = groups[groupIndex];
      if (groupIndex > 0) {
        final previousGroup = groups[groupIndex - 1];
        widgets.add(
          _ServiceChangeBanner(
            stationName: previousGroup.stations.isEmpty
                ? 'the transfer station'
                : previousGroup.stations.last.name,
            nextService: group.serviceName,
          ),
        );
        widgets.add(const SizedBox(height: 8));
      }
      widgets.add(
        SoftCard(
          color: appCardColor(context, Colors.white),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 7),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    _modeIcon(group.mode),
                    size: 18,
                    color: _modeColor(group.mode),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      group.serviceName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ).copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                  Text(
                    '${group.stations.length} stops',
                    style: const TextStyle(fontSize: 8.5, color: kMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: kBorder),
              const SizedBox(height: 8),
              for (var index = 0; index < group.stations.length; index++)
                _buildStationRow(
                  station: group.stations[index],
                  allStations: allStations,
                  isLast: index == group.stations.length - 1,
                  reachedIndex: reachedIndex,
                ),
            ],
          ),
        ),
      );
      if (groupIndex < groups.length - 1) {
        widgets.add(const SizedBox(height: 10));
      }
    }
    return widgets;
  }

  Widget _buildStationRow({
    required TransitStationPoint station,
    required List<TransitStationPoint> allStations,
    required bool isLast,
    required int reachedIndex,
  }) {
    final stationIndex = _stationIndex(station, allStations);
    return _TrackingStationRow(
      station: station,
      index: stationIndex,
      isLast: isLast,
      isReached: stationIndex <= reachedIndex,
      isCurrent: stationIndex == reachedIndex,
    );
  }

  int _stationIndex(
    TransitStationPoint station,
    List<TransitStationPoint> allStations,
  ) {
    for (var index = 0; index < allStations.length; index++) {
      final candidate = allStations[index];
      if (station.id.isNotEmpty && candidate.id == station.id) return index;
      if (candidate.name.trim().toLowerCase() ==
          station.name.trim().toLowerCase()) {
        return index;
      }
    }
    return 0;
  }

  bool _hasBusLeg(TransitRouteResult route) {
    return route.mode == 'Bus' || route.legs.any((leg) => leg.mode == 'Bus');
  }

  String? _reportedLiveStopName(
    List<TransitStationPoint> stations,
    List<RealtimeTransitVehicle> vehicles,
  ) {
    for (final vehicle in vehicles) {
      if (vehicle.currentStopName != null &&
          vehicle.currentStopName!.trim().isNotEmpty) {
        return vehicle.currentStopName;
      }
      final stopId = vehicle.currentStopId;
      if (stopId == null || stopId.isEmpty) continue;
      for (final station in stations) {
        if (station.id == stopId) return station.name;
      }
    }
    return null;
  }
}

class _StationServiceGroup {
  final String mode;
  final String serviceName;
  final List<TransitStationPoint> stations;

  const _StationServiceGroup({
    required this.mode,
    required this.serviceName,
    required this.stations,
  });
}

class _ServiceChangeBanner extends StatelessWidget {
  final String stationName;
  final String nextService;

  const _ServiceChangeBanner({
    required this.stationName,
    required this.nextService,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: appCardColor(context, kYellow),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.swap_horiz_rounded, size: 18, color: kPurple),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change service at $stationName',
                  style: const TextStyle(
                    fontSize: 10,
                    color: kPurple,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Next: $nextService',
                  style: TextStyle(
                    fontSize: 8.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingStatusPill extends StatelessWidget {
  final bool active;
  final bool arrived;

  const _TrackingStatusPill({required this.active, required this.arrived});

  @override
  Widget build(BuildContext context) {
    final color = arrived
        ? kTeal
        : active
        ? kTeal
        : kMutedDark;
    final label = arrived
        ? 'ARRIVED'
        : active
        ? 'LIVE'
        : 'PAUSED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: arrived || active ? kTealSoft : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: arrived || active ? kTeal : kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            arrived ? Icons.check_circle_rounded : Icons.circle,
            size: 9,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingStatusCard extends StatelessWidget {
  final bool monitoring;
  final bool arrived;
  final int? remaining;
  final bool hasLocation;

  const _TrackingStatusCard({
    required this.monitoring,
    required this.arrived,
    required this.remaining,
    required this.hasLocation,
  });

  @override
  Widget build(BuildContext context) {
    final title = arrived
        ? 'Journey complete'
        : monitoring
        ? remaining == null
              ? hasLocation
                    ? 'Location detected'
                    : 'Waiting for your location'
              : remaining == 1
              ? '1 station remaining'
              : '$remaining stations remaining'
        : 'Live tracking is paused';
    final subtitle = arrived
        ? 'You have reached your destination. It will be marked complete automatically in 5 minutes if you do not tap the button.'
        : monitoring
        ? remaining == null && hasLocation
              ? 'Move closer to the starting stop to begin station alerts.'
              : 'Your position will update as you move between stations.'
        : 'Start live tracking to receive station arrival alerts.';
    final color = arrived || monitoring ? kTeal : kPurple;
    return SoftCard(
      color: arrived || monitoring ? kTealSoft : kPurpleSoft,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            arrived
                ? Icons.flag_rounded
                : monitoring
                ? Icons.my_location_rounded
                : Icons.pause_circle_outline_rounded,
            size: 21,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 9, color: kMutedDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusAssignmentCard extends StatelessWidget {
  final RealtimeTransitVehicle? bus;
  final String? status;

  const _BusAssignmentCard({required this.bus, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assigned = bus != null;
    final title = assigned
        ? 'You are on bus ${_vehicleLabel(bus!)}'
        : 'Finding your bus';
    final subtitle =
        status ??
        (assigned
            ? 'Live tracking is following this bus.'
            : 'Stay near your boarding stop while live bus GPS is checked.');

    return SoftCard(
      color: appCardColor(context, assigned ? kTealSoft : kPurpleSoft),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            assigned
                ? Icons.directions_bus_filled_rounded
                : Icons.radar_rounded,
            size: 21,
            color: assigned ? kTeal : kPurple,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _vehicleLabel(RealtimeTransitVehicle vehicle) {
    final id = vehicle.id.trim();
    return id.isEmpty ? vehicle.label : id;
  }
}

class _TransitLiveFeedCard extends StatelessWidget {
  final List<RealtimeTransitVehicle> vehicles;
  final RealtimeTransitVehicle? assignedBus;
  final DateTime? updatedAt;
  final bool loading;
  final String? errorMessage;
  final String? reportedStopName;
  final Future<void> Function() onRefresh;

  const _TransitLiveFeedCard({
    required this.vehicles,
    required this.assignedBus,
    required this.updatedAt,
    required this.loading,
    required this.errorMessage,
    required this.reportedStopName,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final railNotPublished =
        errorMessage?.contains(
          'Live rail positions are not currently published',
        ) ??
        false;
    final railOnlyUnavailable = railNotPublished && vehicles.isEmpty;
    final isUnavailable =
        railOnlyUnavailable || (errorMessage != null && updatedAt == null);
    final title = assignedBus != null
        ? 'Assigned bus ${_vehicleLabel(assignedBus!)}'
        : railOnlyUnavailable
        ? 'Live rail positions not available'
        : isUnavailable
        ? 'Live transit feed unavailable'
        : vehicles.isEmpty
        ? 'No live vehicle reported nearby'
        : '${vehicles.length} live ${vehicles.length == 1 ? 'vehicle' : 'vehicles'} on this route';
    final subtitle = assignedBus != null
        ? 'Only the bus assigned to your journey is shown.'
        : railOnlyUnavailable
        ? 'The official feed does not publish live LRT/MRT positions yet. Timetable and GPS station tracking remain available.'
        : railNotPublished && vehicles.isNotEmpty
        ? 'Rail positions are not published yet. Live bus details are shown below.'
        : isUnavailable
        ? 'The timetable is still available. Try refreshing in a moment.'
        : reportedStopName != null
        ? 'A live vehicle is currently reported at $reportedStopName.'
        : errorMessage ??
              (updatedAt == null
                  ? 'Connecting to the official transit feed…'
                  : 'Official bus and train positions update about every 30 seconds.');
    final color = isUnavailable ? kMutedDark : kTeal;

    return SoftCard(
      color: appCardColor(context, kTealSoft),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isUnavailable ? Icons.cloud_off_rounded : Icons.sensors_rounded,
                size: 21,
                color: color,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (updatedAt != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Feed checked ${_liveTimeLabel(updatedAt!)} MYT',
                        style: TextStyle(
                          fontSize: 8,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: loading ? null : () => onRefresh(),
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 19),
                color: kTeal,
                tooltip: 'Refresh live transit data',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (vehicles.isNotEmpty) ...[
            const SizedBox(height: 9),
            for (final vehicle in vehicles.take(4)) ...[
              _LiveVehicleDetailsCard(vehicle: vehicle),
              if (vehicle != vehicles.take(4).last) const SizedBox(height: 7),
            ],
            if (vehicles.length > 4) ...[
              const SizedBox(height: 7),
              Text(
                '+${vehicles.length - 4} more vehicles are on the route',
                style: TextStyle(
                  fontSize: 8,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _vehicleLabel(RealtimeTransitVehicle vehicle) {
    final id = vehicle.id.trim();
    return id.isEmpty ? vehicle.label : id;
  }
}

class _LiveVehicleDetailsCard extends StatelessWidget {
  final RealtimeTransitVehicle vehicle;

  const _LiveVehicleDetailsCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBus = vehicle.mode == 'Bus';
    final vehicleId = vehicle.id.trim().isEmpty ? vehicle.label : vehicle.id;
    final currentStop =
        vehicle.currentStopName ??
        (vehicle.currentStopId?.trim().isEmpty ?? true
            ? 'Stop not reported'
            : vehicle.currentStopId!.trim());

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isBus
                    ? Icons.directions_bus_filled_rounded
                    : Icons.train_rounded,
                size: 16,
                color: isBus ? kTeal : kPurple,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${isBus ? 'Bus' : 'Train'} ID: $vehicleId',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined, size: 16, color: kTeal),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT STOP',
                      style: TextStyle(
                        fontSize: 7,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentStop,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (vehicle.currentStopEstimated) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Nearest stop based on the bus GPS position',
                        style: TextStyle(
                          fontSize: 7.5,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'GPS ${vehicle.latitude.toStringAsFixed(4)}, ${vehicle.longitude.toStringAsFixed(4)}',
            style: TextStyle(
              fontSize: 7.5,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingStat extends StatelessWidget {
  final String label;
  final String value;

  const _TrackingStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: KickerStyle.small.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ).copyWith(color: theme.colorScheme.onSurface),
        ),
      ],
    );
  }
}

class _TrackingStationRow extends StatelessWidget {
  final TransitStationPoint station;
  final int index;
  final bool isLast;
  final bool isReached;
  final bool isCurrent;

  const _TrackingStationRow({
    required this.station,
    required this.index,
    required this.isLast,
    required this.isReached,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isCurrent
        ? kTeal
        : isReached
        ? kPurple
        : kMuted;
    final label = isCurrent
        ? 'Current stop'
        : isReached
        ? 'Passed'
        : index == 0
        ? 'Starting stop'
        : 'Upcoming';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 25,
          child: Column(
            children: [
              Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isReached ? color : appFieldSurface(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.3),
                ),
                child: isReached
                    ? Icon(
                        isCurrent ? Icons.my_location_rounded : Icons.check,
                        size: 11,
                        color: Colors.white,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 8,
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              if (!isLast)
                Container(
                  width: 1,
                  height: 28,
                  color: isReached ? kPurple : kBorder,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    station.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isReached
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

IconData _modeIcon(String mode) {
  if (mode == 'Bus') return Icons.directions_bus_filled_rounded;
  if (mode == 'Walk') return Icons.directions_walk_rounded;
  if (mode == 'Mixed') return Icons.alt_route_rounded;
  return Icons.train_rounded;
}

Color _modeColor(String mode) {
  if (mode == 'Bus') return kTeal;
  if (mode == 'Walk') return kMutedDark;
  return kPurple;
}

String _liveTimeLabel(DateTime time) {
  // Realtime timestamps are stored as UTC so a phone configured for another
  // timezone cannot make the feed appear several hours old or in the future.
  final malaysiaTime = time.toUtc().add(const Duration(hours: 8));
  final hour = malaysiaTime.hour % 12 == 0 ? 12 : malaysiaTime.hour % 12;
  final minute = malaysiaTime.minute.toString().padLeft(2, '0');
  final period = malaysiaTime.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}
