import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transit_models.dart';
import '../providers/app_state.dart';
import '../widgets/smart_move_widgets.dart';
import 'auth_page.dart';

class SavedPage extends StatelessWidget {
  final ValueChanged<String> onMessage;

  const SavedPage({required this.onMessage, super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(7, 0, 7, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            title: 'Saved',
            avatarLabel: avatarInitials(state.profileName),
            avatarImagePath: state.profileImagePath,
          ),
          const SizedBox(height: 22),
          PageTitle(
            kicker: 'YOUR SHORTCUTS',
            title: 'Saved & history',
            trailing: GestureDetector(
              onTap: () => onMessage('More saved options'),
              child: const Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: kMutedDark,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SectionHeading(
            title: 'Favourite places',
            trailing: state.isGuest ? 'Sign in to add' : '+ Add new',
            onTrailingTap: () {
              if (state.isGuest) {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
              } else {
                onMessage('Add a favourite route from the Plan page');
              }
            },
          ),
          const SizedBox(height: 8),
          if (state.isGuest)
            const SoftCard(
              color: kPurpleSoft,
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 16, color: kPurple),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Guest mode cannot save favourite routes. Sign in to unlock this feature.',
                      style: TextStyle(fontSize: 9, color: kInk),
                    ),
                  ),
                ],
              ),
            )
          else if (state.savedPlaces.isEmpty)
            const SoftCard(
              child: Text(
                'No favourite routes yet. Save one from the Plan page.',
                style: TextStyle(fontSize: 9, color: kMuted),
              ),
            )
          else
            ...state.savedPlaces.map(
              (place) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: SavedItem(
                  icon: Icons.bookmark_outline_rounded,
                  iconBackground: kPurpleSoft,
                  title: place.title,
                  subtitle: place.subtitle,
                  onTap: () => onMessage('${place.title} route'),
                ),
              ),
            ),
          const SizedBox(height: 13),
          SectionHeading(
            title: 'Recent journeys',
            trailing: 'Clear',
            onTrailingTap: state.recentJourneys.isEmpty
                ? null
                : state.clearJourneys,
          ),
          const SizedBox(height: 8),
          if (state.recentJourneys.isEmpty)
            const SoftCard(
              child: Text(
                'Your completed journeys will appear here.',
                style: TextStyle(fontSize: 9, color: kMuted),
              ),
            )
          else
            ...state.recentJourneys.map(
              (journey) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: SavedItem(
                  icon: Icons.train_rounded,
                  iconBackground: kPurpleSoft,
                  title: '${journey.from} → ${journey.to}',
                  subtitle:
                      '${_dayLabel(journey)}   ${journey.service} · ${journey.durationMinutes} min',
                  onTap: () => onMessage('Reopen journey'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _dayLabel(JourneyRecord journey) {
    return DateTime.now().difference(journey.createdAt).inHours < 24
        ? 'TODAY'
        : 'YESTERDAY';
  }
}

class SavedItem extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SavedItem({
    required this.icon,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 27,
              height: 27,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: kPurple),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 10,
                      color: kInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 8.5, color: kMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 16, color: kMuted),
          ],
        ),
      ),
    );
  }
}
