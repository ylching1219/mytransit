import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/transit_data_service.dart';
import '../widgets/smart_move_widgets.dart';
import '../widgets/transit_route_map.dart';

class RouteResultsPage extends StatefulWidget {
  final String from;
  final String to;
  final String? departureTimeLabel;

  const RouteResultsPage({
    required this.from,
    required this.to,
    required this.departureTimeLabel,
    super.key,
  });

  @override
  State<RouteResultsPage> createState() => _RouteResultsPageState();
}

class _RouteResultsPageState extends State<RouteResultsPage> {
  String _selectedMode = 'All';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final routes = state.routeOptions;
    const modes = ['Bus', 'LRT', 'MRT', 'Mixed'];
    final visibleModes = _selectedMode == 'All'
        ? modes
        : <String>[_selectedMode];
    final groupedRoutes = <String, Map<String, List<TransitRouteResult>>>{
      for (final mode in modes) mode: <String, List<TransitRouteResult>>{},
    };
    for (final route in routes) {
      final services = groupedRoutes.putIfAbsent(
        route.mode,
        () => <String, List<TransitRouteResult>>{},
      );
      services.putIfAbsent(route.serviceName, () => []).add(route);
    }

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(7, 0, 7, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(
                title: 'Available routes',
                avatarLabel: avatarInitials(state.profileName),
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 19,
                        color: kMutedDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: PageTitle(
                      kicker: 'ROUTE OPTIONS',
                      title: 'Available routes',
                      trailing: Text(
                        '2 of 2',
                        style: TextStyle(
                          fontSize: 9,
                          color: kMuted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              SoftCard(
                color: kTealSoft,
                padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
                child: Row(
                  children: [
                    const Icon(Icons.alt_route_rounded, color: kTeal, size: 21),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.from} → ${widget.to}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: kInk,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.departureTimeLabel == null
                                ? 'All scheduled departures · Official timetable'
                                : 'Departures within 30 minutes of ${widget.departureTimeLabel} · Official timetable',
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: kMutedDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Preferred transport: ${state.preferredTransport}',
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: kPurple,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionHeading(
                title: 'Routes by service',
                trailing: '${routes.length} found',
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final mode in ['All', ...modes])
                    if (mode == 'All' || groupedRoutes[mode]!.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _selectedMode = mode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedMode == mode
                                ? kPurple
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedMode == mode ? kPurple : kBorder,
                            ),
                          ),
                          child: Text(
                            '$mode${mode == 'All' ? ' · ${routes.length}' : ' · ${groupedRoutes[mode]!.values.fold<int>(0, (total, serviceRoutes) => total + serviceRoutes.length)}'}',
                            style: TextStyle(
                              fontSize: 9,
                              color: _selectedMode == mode
                                  ? Colors.white
                                  : kMutedDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 9),
              if (routes.isEmpty)
                const SoftCard(
                  child: Text(
                    'No journey was found after the selected time.',
                    style: TextStyle(fontSize: 10, color: kMutedDark),
                  ),
                )
              else
                for (final mode in visibleModes)
                  if (groupedRoutes[mode]!.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 7, bottom: 7),
                      child: Row(
                        children: [
                          Icon(
                            _modeIcon(mode),
                            size: 17,
                            color: _modeColor(mode),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            mode,
                            style: const TextStyle(
                              fontSize: 12,
                              color: kInk,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${groupedRoutes[mode]!.values.fold<int>(0, (total, serviceRoutes) => total + serviceRoutes.length)} departures',
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: kMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final service in groupedRoutes[mode]!.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(23, 5, 0, 6),
                        child: Text(
                          service.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: kPurple,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      for (var index = 0; index < service.value.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: RouteOptionCard(
                            route: service.value[index],
                            recommended: index == 0,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RouteDetailPage(
                                  route: service.value[index],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
              const SizedBox(height: 7),
              const Center(
                child: Text(
                  'Tap a route to see stops and journey details.',
                  style: TextStyle(fontSize: 8.5, color: kMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RouteOptionCard extends StatelessWidget {
  final TransitRouteResult route;
  final bool recommended;
  final VoidCallback? onTap;

  const RouteOptionCard({
    required this.route,
    required this.recommended,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: recommended ? kPurpleSoft : Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TransitDataService.formatTime(route.departureTime),
                  style: const TextStyle(
                    fontSize: 13,
                    color: kInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'DEPART',
                  style: TextStyle(
                    fontSize: 7,
                    letterSpacing: .7,
                    color: kMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 34, color: kBorder),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          route.serviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: kPurple,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 5),
                        const Text(
                          'BEST',
                          style: TextStyle(
                            fontSize: 7,
                            color: kTeal,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${route.fromStopName} → ${route.toStopName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: kInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (route.legs.length > 1) ...[
                    const SizedBox(height: 3),
                    Text(
                      _legSummary(route.legs),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: kPurple,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    'Arrive ${TransitDataService.formatTime(route.arrivalTime)} · ${route.durationMinutes} min · ${route.stopsBetween} stops',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8.5, color: kMutedDark),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _fareLabel(route.fare),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: kTeal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.chevron_right_rounded, size: 18, color: kMuted),
          ],
        ),
      ),
    );
  }
}

class RouteDetailPage extends StatelessWidget {
  final TransitRouteResult route;

  const RouteDetailPage({required this.route, super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isNextJourney = state.isNextRoute(route);
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(7, 0, 7, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(
                title: 'Route details',
                avatarLabel: avatarInitials(state.profileName),
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 19,
                        color: kMutedDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: PageTitle(
                      kicker: 'JOURNEY DETAILS',
                      title: 'Your selected route',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              SoftCard(
                color: kPurpleSoft,
                padding: const EdgeInsets.fromLTRB(11, 10, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _modeIcon(route.mode),
                          color: _modeColor(route.mode),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            route.serviceName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: kInk,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Text(
                      '${route.fromStopName} → ${route.toStopName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: kInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _DetailStat(
                            label: 'DEPART',
                            value: TransitDataService.formatTime(
                              route.departureTime,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _DetailStat(
                            label: 'ARRIVE',
                            value: TransitDataService.formatTime(
                              route.arrivalTime,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _DetailStat(
                            label: 'DURATION',
                            value: '${route.durationMinutes} min',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (isNextJourney)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: kTealSoft,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: kTeal),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 18, color: kTeal),
                      SizedBox(width: 8),
                      Text(
                        'This is your next journey',
                        style: TextStyle(
                          fontSize: 10,
                          color: kTeal,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: () {
                      state.markNextRoute(route);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Marked as your next journey.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.flag_outlined, size: 17),
                    label: const Text(
                      'Mark as next journey',
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
              const SizedBox(height: 14),
              const SectionHeading(title: 'Route map'),
              const SizedBox(height: 8),
              TransitRouteMap(route: route),
              if (route.legs.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionHeading(title: 'Journey steps'),
                const SizedBox(height: 8),
                SoftCard(
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                  child: Column(
                    children: [
                      for (var index = 0; index < route.legs.length; index++)
                        _JourneyLegRow(
                          leg: route.legs[index],
                          isLast: index == route.legs.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const SectionHeading(title: 'Journey information'),
              const SizedBox(height: 8),
              SoftCard(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.trip_origin_rounded,
                      label: 'Starting station',
                      value: route.fromStopName,
                    ),
                    const Divider(height: 16, color: kBorder),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Destination',
                      value: route.toStopName,
                    ),
                    const Divider(height: 16, color: kBorder),
                    _InfoRow(
                      icon: Icons.straighten_rounded,
                      label: 'Stops between',
                      value: '${route.stopsBetween} stops',
                    ),
                    const Divider(height: 16, color: kBorder),
                    _InfoRow(
                      icon: _modeIcon(route.mode),
                      label: 'Service type',
                      value: route.mode,
                    ),
                    const Divider(height: 16, color: kBorder),
                    _InfoRow(
                      icon: Icons.payments_outlined,
                      label: 'Adult / cashless fare',
                      value: _fareDetailLabel(route.fare),
                    ),
                    const Divider(height: 16, color: kBorder),
                    const _InfoRow(
                      icon: Icons.verified_outlined,
                      label: 'Data source',
                      value: 'Official GTFS + MyRapid fares',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text(
                  'Timetable times may change when the official feed is updated.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8.5, color: kMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fareLabel(TransitFare? fare) {
  if (fare == null) return 'Fare unavailable';
  if (fare.isZoneBased) {
    return 'Adult from RM${fare.adult} · Zone-based bus fare';
  }
  return 'Cashless RM${fare.cashless} · Adult RM${fare.adult}';
}

String _fareDetailLabel(TransitFare? fare) {
  if (fare == null) return 'Unavailable';
  if (fare.isZoneBased) {
    return 'From RM${fare.adult} · Zone-based';
  }
  return 'RM${fare.adult} / RM${fare.cashless}';
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
  if (mode == 'Mixed') return kPurple;
  return kPurple;
}

String _legSummary(List<TransitJourneyLeg> legs) {
  return legs
      .map((leg) {
        if (leg.isWalking) return 'Walk ${leg.durationMinutes} min';
        return leg.mode;
      })
      .join(' → ');
}

class _JourneyLegRow extends StatefulWidget {
  final TransitJourneyLeg leg;
  final bool isLast;

  const _JourneyLegRow({required this.leg, required this.isLast});

  @override
  State<_JourneyLegRow> createState() => _JourneyLegRowState();
}

class _JourneyLegRowState extends State<_JourneyLegRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final leg = widget.leg;
    final canShowStops = !leg.isWalking && leg.passingStops.isNotEmpty;
    return Column(
      children: [
        InkWell(
          onTap: canShowStops
              ? () => setState(() => _expanded = !_expanded)
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: leg.isWalking ? kTealSoft : kPurpleSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _modeIcon(leg.mode),
                    size: 15,
                    color: _modeColor(leg.mode),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leg.isWalking
                            ? 'Walk · ${leg.durationMinutes} min'
                            : '${leg.mode} · ${leg.serviceName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: kInk,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${leg.fromStopName} → ${leg.toStopName}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: kMutedDark),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        canShowStops
                            ? 'Tap to ${_expanded ? 'hide' : 'show'} ${leg.passingStops.length} stations'
                            : '${TransitDataService.formatTime(leg.departureTime)} → ${TransitDataService.formatTime(leg.arrivalTime)}',
                        style: TextStyle(
                          fontSize: 8.5,
                          color: canShowStops ? kPurple : kMuted,
                          fontWeight: canShowStops
                              ? FontWeight.w800
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canShowStops)
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: kPurple,
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && canShowStops)
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 7, 4, 2),
            child: Column(
              children: [
                for (var index = 0; index < leg.passingStops.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                index == 0 ||
                                    index == leg.passingStops.length - 1
                                ? kTealSoft
                                : kBackground,
                            shape: BoxShape.circle,
                            border: Border.all(color: kTeal, width: 1),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 7,
                              color: kTeal,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            leg.passingStops[index],
                            style: const TextStyle(
                              fontSize: 9,
                              color: kMutedDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (!widget.isLast) const Divider(height: 18, color: kBorder),
      ],
    );
  }
}

class _DetailStat extends StatelessWidget {
  final String label;
  final String value;

  const _DetailStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: KickerStyle.small),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            color: kInk,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: kTeal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 9, color: kMutedDark),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              color: kInk,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
