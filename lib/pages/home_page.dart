import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/transit_data_service.dart';
import '../widgets/smart_move_widgets.dart';
import 'live_tracking_page.dart';

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
    final theme = Theme.of(context);
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
                    color: appCardColor(context, kTealSoft),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.gps_fixed_rounded, size: 10, color: kTeal),
                      SizedBox(width: 4),
                      Text(
                        'GPS on',
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colorScheme.primary,
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
              color: appCardColor(context, Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: appCardColor(context, kTealSoft),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      color: kTeal,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search a destination',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Start from your current location',
                          style: TextStyle(
                            fontSize: 9,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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
            trailing: state.nextRoute == null ? null : 'Live tracking',
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
            Dismissible(
              key: ValueKey(
                'next-journey-${state.nextRoute!.fromStopId}-${state.nextRoute!.toStopId}',
              ),
              direction: DismissDirection.endToStart,
              background: const _SwipeRemoveBackground(),
              onDismissed: (_) {
                context.read<AppState>().clearNextRoute();
                onMessage('Next journey removed');
              },
              child: GestureDetector(
                onTap: () => _openNextJourney(context, state.nextRoute!),
                child: JourneyCard(route: state.nextRoute!),
              ),
            ),
        ],
      ),
    );
  }

  void _openNextJourney(BuildContext context, TransitRouteResult route) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LiveTrackingPage(route: route)));
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        isScrollControlled: true,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);
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
                        Expanded(
                          child: Text(
                            'Nearby stops',
                            style: TextStyle(
                              fontSize: 16,
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    Text(
                      'Closest bus and rail stops based on your current location',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
                            color: appCardColor(sheetContext, Colors.white),
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
                                    color: appCardColor(
                                      sheetContext,
                                      isBus ? kTealSoft : kPurpleSoft,
                                    ),
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
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${stop.mode} · ${_formatDistance(stop.distanceMeters)} away',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
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
    final theme = Theme.of(context);
    final iconBackground = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: .12)
        : Colors.white.withValues(alpha: .65);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.fromLTRB(6, 8, 5, 7),
        decoration: BoxDecoration(
          color: appCardColor(context, color),
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
                color: iconBackground,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                icon,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurface,
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

class _SwipeRemoveBackground extends StatelessWidget {
  const _SwipeRemoveBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5D9D3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEABCB3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: Color(0xFFB95F52)),
          SizedBox(width: 5),
          Text(
            'Remove',
            style: TextStyle(
              color: Color(0xFFB95F52),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class JourneyCard extends StatelessWidget {
  final TransitRouteResult route;

  const JourneyCard({required this.route, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modeSummary = _journeyModeSummary(route);
    final fareLabel = route.fare == null
        ? 'Unavailable'
        : 'RM ${route.fare!.adult}';
    return SoftCard(
      color: appCardColor(context, kTealSoft),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: .62),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _modeIcon(route.mode),
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NEXT JOURNEY',
                      style: TextStyle(
                        fontSize: 7,
                        letterSpacing: .7,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      route.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (modeSummary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        modeSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  route.mode.toUpperCase(),
                  style: TextStyle(
                    fontSize: 7,
                    letterSpacing: .4,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: .58),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const _JourneyDot(color: kTeal),
                    Container(width: 1, height: 34, color: kBorder),
                    const _JourneyDot(color: kPurple),
                  ],
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _JourneyStopText(
                        label: 'FROM',
                        value: route.fromStopName,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      _JourneyStopText(
                        label: 'TO',
                        value: route.toStopName,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _JourneyMetric(
                  icon: Icons.play_arrow_rounded,
                  label: 'DEPART',
                  value: TransitDataService.formatTime(route.departureTime),
                ),
              ),
              Container(width: 1, height: 25, color: kBorder),
              Expanded(
                child: _JourneyMetric(
                  icon: Icons.flag_outlined,
                  label: 'ARRIVE',
                  value: TransitDataService.formatTime(route.arrivalTime),
                ),
              ),
              Container(width: 1, height: 25, color: kBorder),
              Expanded(
                child: _JourneyMetric(
                  icon: Icons.schedule_rounded,
                  label: 'DURATION',
                  value: '${route.durationMinutes} min',
                ),
              ),
              Container(width: 1, height: 25, color: kBorder),
              Expanded(
                child: _JourneyMetric(
                  icon: Icons.payments_outlined,
                  label: 'FARE',
                  value: fareLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _journeyModeSummary(TransitRouteResult route) {
    final modes = <String>[];
    for (final leg in route.legs) {
      if (leg.isWalking) continue;
      if (modes.isEmpty || modes.last != leg.mode) modes.add(leg.mode);
    }
    return modes.length > 1 ? modes.join(' → ') : null;
  }

  IconData _modeIcon(String mode) {
    final value = mode.toLowerCase();
    if (value.contains('bus')) return Icons.directions_bus_rounded;
    if (value.contains('walk')) return Icons.directions_walk_rounded;
    return Icons.train_rounded;
  }
}

class _JourneyDot extends StatelessWidget {
  final Color color;

  const _JourneyDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}

class _JourneyStopText extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _JourneyStopText({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 7,
            letterSpacing: .6,
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _JourneyMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _JourneyMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 6.5,
              letterSpacing: .35,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyNextJourneyCard extends StatelessWidget {
  const EmptyNextJourneyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      color: appCardColor(context, Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: appCardColor(context, kPurpleSoft),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.flag_outlined, size: 17, color: kPurple),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No next route selected',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Find a route and mark it here for quick access.',
                  style: TextStyle(
                    fontSize: 8.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            size: 17,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}