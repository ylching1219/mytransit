import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/transit_data_service.dart';
import '../widgets/smart_move_widgets.dart';
import 'route_results_page.dart';

class HomePage extends StatelessWidget {
  final VoidCallback onPlanTap;
  final VoidCallback onSavedTap;
  final VoidCallback onHistoryTap;
  final VoidCallback onAlertsTap;
  final ValueChanged<String> onMessage;

  const HomePage({
    required this.onPlanTap,
    required this.onSavedTap,
    required this.onHistoryTap,
    required this.onAlertsTap,
    required this.onMessage,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(7, 0, 7, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            title: '',
            greetingName: state.isGuest ? 'Guest' : state.profileName,
            avatarLabel: avatarInitials(state.profileName),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: PageTitle(
                  kicker: 'YOUR NEXT MOVE',
                  title: 'Where are you going?',
                ),
              ),
              GestureDetector(
                onTap: () async {
                  if (!state.permissionGranted) {
                    await state.requestLocationPermission();
                  }
                  if (!state.gpsEnabled) await state.requestGps();
                  onMessage(
                    state.permissionGranted && state.gpsEnabled
                        ? 'GPS is on'
                        : 'Location access is not available yet',
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: kTealSoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.gps_fixed_rounded, size: 10, color: kTeal),
                      SizedBox(width: 4),
                      Text(
                        'GPS on',
                        style: TextStyle(
                          fontSize: 9,
                          color: kTeal,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          GestureDetector(
            onTap: onPlanTap,
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kTealSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      color: kTeal,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search a destination',
                          style: TextStyle(
                            fontSize: 10,
                            color: kInk,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Start from your current location',
                          style: TextStyle(fontSize: 9, color: kMuted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: kTeal,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ShortcutTile(
                  icon: Icons.location_on_outlined,
                  label: 'Nearby\nstops',
                  color: kTealSoft,
                  onTap: () => _showNearbyStops(context),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ShortcutTile(
                  icon: Icons.bookmark_outline_rounded,
                  label: 'Saved\nplaces',
                  color: kPurpleSoft,
                  onTap: onSavedTap,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ShortcutTile(
                  icon: Icons.notifications_none_rounded,
                  label: 'Live service\nalerts',
                  color: kPeach,
                  onTap: onAlertsTap,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ShortcutTile(
                  icon: Icons.history_rounded,
                  label: 'Journey\nhistory',
                  color: kYellow,
                  onTap: onHistoryTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionHeading(
            title: 'Next journey',
            trailing: state.nextRoute == null ? null : 'View details',
            onTrailingTap: state.nextRoute == null
                ? null
                : () => _openNextJourney(context, state.nextRoute!),
          ),
          const SizedBox(height: 8),
          if (state.nextRoute == null)
            GestureDetector(
              onTap: onPlanTap,
              child: const EmptyNextJourneyCard(),
            )
          else
            GestureDetector(
              onTap: () => _openNextJourney(context, state.nextRoute!),
              child: JourneyCard(route: state.nextRoute!),
            ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => onMessage('Trip reminder dismissed'),
            child: const SoftCard(
              color: kYellow,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 18,
                    color: Color(0xFFB08B2F),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Travelling today?',
                          style: TextStyle(
                            fontSize: 9,
                            color: kInk,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Turn on alerts before you start your journey.',
                          style: TextStyle(fontSize: 8.5, color: kMutedDark),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.close_rounded, size: 16, color: Color(0xFFB08B2F)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openNextJourney(BuildContext context, TransitRouteResult route) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RouteDetailPage(route: route)));
  }

  Future<void> _showNearbyStops(BuildContext context) async {
    final state = context.read<AppState>();
    onMessage('Finding nearby transit stops...');

    try {
      final location = await state.getCurrentLocation();
      if (!context.mounted) return;
      if (location?.latitude == null || location?.longitude == null) {
        onMessage(
          'Turn on GPS and allow location access to find nearby stops.',
        );
        return;
      }

      final stops = await state.findNearbyTransitStops(
        latitude: location!.latitude!,
        longitude: location.longitude!,
      );
      if (!context.mounted) return;
      if (stops.isEmpty) {
        onMessage('No transit stop was found within 1.5 km.');
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: kBackground,
        isScrollControlled: true,
        builder: (sheetContext) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .58,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Nearby stops',
                            style: TextStyle(
                              fontSize: 16,
                              color: kInk,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: kMutedDark,
                        ),
                      ],
                    ),
                    const Text(
                      'Closest bus and rail stops based on your current location',
                      style: TextStyle(fontSize: 10, color: kMutedDark),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: stops.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 7),
                        itemBuilder: (_, index) {
                          final stop = stops[index];
                          final isBus = stop.mode.toLowerCase().contains('bus');
                          return SoftCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isBus ? kTealSoft : kPurpleSoft,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(
                                    isBus
                                        ? Icons.directions_bus_filled_rounded
                                        : Icons.train_rounded,
                                    size: 16,
                                    color: isBus ? kTeal : kPurple,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stop.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: kInk,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${stop.mode} · ${_formatDistance(stop.distanceMeters)} away',
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: kMutedDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (_) {
      if (context.mounted) {
        onMessage('Nearby stops are unavailable right now.');
      }
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

class ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ShortcutTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.fromLTRB(6, 8, 5, 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 23,
              height: 23,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 14, color: kMutedDark),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      color: kInk,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JourneyCard extends StatelessWidget {
  final TransitRouteResult route;

  const JourneyCard({required this.route, super.key});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: kTealSoft,
      padding: const EdgeInsets.fromLTRB(10, 9, 9, 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(_modeIcon(route.mode), size: 12, color: kTeal),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  route.serviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: kTeal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                TransitDataService.formatTime(route.departureTime),
                style: const TextStyle(
                  fontSize: 9,
                  color: kInk,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Flexible(
                child: Text(
                  route.fromStopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: kInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              const Expanded(child: JourneyLine()),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  route.toStopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: kInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 16, color: kTeal),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 11, color: kMuted),
              const SizedBox(width: 3),
              Text(
                '${route.durationMinutes} min',
                style: const TextStyle(fontSize: 8.5, color: kMuted),
              ),
              const SizedBox(width: 12),
              Text(
                '${route.stopsBetween} stops',
                style: const TextStyle(fontSize: 8.5, color: kMuted),
              ),
              const SizedBox(width: 12),
              Text(
                route.fare == null
                    ? 'Fare unavailable'
                    : 'RM ${route.fare!.adult}',
                style: const TextStyle(fontSize: 8.5, color: kMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _modeIcon(String mode) {
    final value = mode.toLowerCase();
    if (value.contains('bus')) return Icons.directions_bus_rounded;
    if (value.contains('walk')) return Icons.directions_walk_rounded;
    return Icons.train_rounded;
  }
}

class EmptyNextJourneyCard extends StatelessWidget {
  const EmptyNextJourneyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kPurpleSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.flag_outlined, size: 17, color: kPurple),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No next route selected',
                  style: TextStyle(
                    fontSize: 10,
                    color: kInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Find a route and mark it here for quick access.',
                  style: TextStyle(fontSize: 8.5, color: kMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 17, color: kPurple),
        ],
      ),
    );
  }
}

class JourneyLine extends StatelessWidget {
  const JourneyLine({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 2, color: const Color(0xFF9A8CC6))),
        const SizedBox(width: 4),
        ...List.generate(
          4,
          (index) => Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: kPurple,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
