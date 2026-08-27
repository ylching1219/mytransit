import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/smart_move_widgets.dart';

class HomePage extends StatelessWidget {
  final VoidCallback onPlanTap;
  final ValueChanged<String> onMessage;

  const HomePage({required this.onPlanTap, required this.onMessage, super.key});

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
            avatarImagePath: state.profileImagePath,
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
                  onTap: () => onMessage('Showing nearby stops'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ShortcutTile(
                  icon: Icons.bookmark_outline_rounded,
                  label: 'Saved\nplaces',
                  color: kPurpleSoft,
                  onTap: () => onMessage('Saved places'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ShortcutTile(
                  icon: Icons.notifications_none_rounded,
                  label: 'Live service\nalerts',
                  color: kPeach,
                  onTap: () => onMessage('No active service alerts'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ShortcutTile(
                  icon: Icons.history_rounded,
                  label: 'Journey\nhistory',
                  color: kYellow,
                  onTap: () => onMessage('Journey history'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionHeading(title: 'Next journey', trailing: 'View details'),
          const SizedBox(height: 8),
          const JourneyCard(),
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
          const SizedBox(height: 12),
          const WeatherCard(),
        ],
      ),
    );
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
            const Spacer(),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: kInk,
                height: 1.12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JourneyCard extends StatelessWidget {
  const JourneyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: kPurpleSoft,
      padding: const EdgeInsets.fromLTRB(10, 9, 9, 8),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.train_rounded, size: 12, color: kPurple),
              SizedBox(width: 5),
              Text(
                'LRT Kelana Jaya',
                style: TextStyle(
                  fontSize: 9,
                  color: kPurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Spacer(),
              Text(
                '8:30 AM',
                style: TextStyle(
                  fontSize: 9,
                  color: kInk,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Row(
            children: [
              Text(
                'KL Sentral',
                style: TextStyle(
                  fontSize: 10,
                  color: kInk,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 7),
              Expanded(child: JourneyLine()),
              SizedBox(width: 7),
              Text(
                'Pasar Seni',
                style: TextStyle(
                  fontSize: 10,
                  color: kInk,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 16, color: kPurple),
            ],
          ),
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(Icons.schedule_rounded, size: 11, color: kMuted),
              SizedBox(width: 3),
              Text('12 min', style: TextStyle(fontSize: 8.5, color: kMuted)),
              SizedBox(width: 12),
              Text('3 stops', style: TextStyle(fontSize: 8.5, color: kMuted)),
              SizedBox(width: 12),
              Text('RM 1.20', style: TextStyle(fontSize: 8.5, color: kMuted)),
            ],
          ),
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

class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final forecast = state.currentForecast;
    return SoftCard(
      color: kTealSoft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          const Icon(Icons.cloud_outlined, size: 20, color: kTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kuala Lumpur weather',
                  style: TextStyle(
                    fontSize: 9,
                    color: kInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.weatherLoading
                      ? 'Loading MetMalaysia forecast...'
                      : forecast == null
                      ? state.weatherError ?? 'Forecast unavailable'
                      : '${forecast.summaryForecast} · ${forecast.minTemp}°-${forecast.maxTemp}°C',
                  style: const TextStyle(fontSize: 8.5, color: kMutedDark),
                ),
              ],
            ),
          ),
          if (!state.weatherLoading)
            IconButton(
              onPressed: state.refreshWeather,
              icon: const Icon(Icons.refresh_rounded, size: 15, color: kTeal),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
