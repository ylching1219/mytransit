import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transit_models.dart';
import '../providers/app_state.dart';
import '../widgets/smart_move_widgets.dart';
import 'auth_page.dart';
import 'route_results_page.dart';

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
            const SizedBox(
              width: double.infinity,
              child: SoftCard(
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
              ),
            )
          else if (state.savedPlaces.isEmpty)
            const SizedBox(
              width: double.infinity,
              child: SoftCard(
                child: Text(
                  'No favourite routes yet. Save one from the Plan page.',
                  style: TextStyle(fontSize: 9, color: kMuted),
                ),
              ),
            )
          else
            ...state.savedPlaces.map(
              (place) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: SavedItem(
                  icon: Icons.bookmark_outline_rounded,
                  iconBackground: kPurpleSoft,
                  eyebrow: 'FAVOURITE ROUTE',
                  title: place.title,
                  subtitle: place.subtitle,
                  onDelete: () => _confirmRemoveFavorite(context, place),
                  onTap: () {
                    final locations = _splitRoute(place.title);
                    if (locations == null) {
                      onMessage(
                        'This favourite route needs to be saved again.',
                      );
                      return;
                    }
                    _searchSavedRoute(
                      context,
                      from: locations[0],
                      to: locations[1],
                    );
                  },
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
            const SizedBox(
              width: double.infinity,
              child: SoftCard(
                child: Text(
                  'Your completed journeys will appear here.',
                  style: TextStyle(fontSize: 9, color: kMuted),
                ),
              ),
            )
          else
            ...state.recentJourneys.map(
              (journey) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: SavedItem(
                  icon: _journeyIcon(journey.service),
                  iconBackground: _journeyIconBackground(journey.service),
                  eyebrow: _dayLabel(journey),
                  title: '${journey.from} → ${journey.to}',
                  subtitle:
                      '${journey.service} · ${journey.durationMinutes} min',
                  onTap: () => _searchSavedRoute(
                    context,
                    from: journey.from,
                    to: journey.to,
                  ),
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

  IconData _journeyIcon(String service) {
    final value = service.toLowerCase();
    if (value.contains('bus')) return Icons.directions_bus_rounded;
    if (value.contains('walk')) return Icons.directions_walk_rounded;
    if (value.contains('mixed') || value.contains('+')) {
      return Icons.alt_route_rounded;
    }
    return Icons.train_rounded;
  }

  Color _journeyIconBackground(String service) {
    final value = service.toLowerCase();
    if (value.contains('bus')) return kTealSoft;
    if (value.contains('walk')) return kYellow;
    if (value.contains('mixed') || value.contains('+')) return kPeach;
    return kPurpleSoft;
  }

  List<String>? _splitRoute(String title) {
    const separator = ' → ';
    final separatorIndex = title.indexOf(separator);
    if (separatorIndex <= 0 ||
        separatorIndex >= title.length - separator.length) {
      return null;
    }
    final from = title.substring(0, separatorIndex).trim();
    final to = title.substring(separatorIndex + separator.length).trim();
    if (from.isEmpty || to.isEmpty) return null;
    return [from, to];
  }

  Future<void> _searchSavedRoute(
    BuildContext context, {
    required String from,
    required String to,
  }) async {
    final state = context.read<AppState>();
    onMessage('Finding routes from $from to $to...');
    final found = await state.planJourney(
      from: from,
      to: to,
      recordRecent: false,
    );
    if (!context.mounted) return;
    if (!found) {
      onMessage(state.transitError ?? 'No route was found for this journey.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RouteResultsPage(from: from, to: to, departureTimeLabel: null),
      ),
    );
  }

  Future<void> _confirmRemoveFavorite(
    BuildContext context,
    SavedPlace place,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove favourite route?'),
        content: Text('Remove ${place.title} from your saved places?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !context.mounted) return;
    final removed = await context.read<AppState>().removeFavoriteRoute(
      place.id,
    );
    if (context.mounted && removed) onMessage('Favourite route removed');
  }
}

class SavedItem extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final String? eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback? onDelete;
  final VoidCallback onTap;

  const SavedItem({
    required this.icon,
    required this.iconBackground,
    this.eyebrow,
    required this.title,
    required this.subtitle,
    this.onDelete,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: kPurple),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null)
                      Text(
                        eyebrow!,
                        style: const TextStyle(
                          fontSize: 7,
                          letterSpacing: .65,
                          color: kMuted,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    if (eyebrow != null) const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: kInk,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 8.5, color: kMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: kMutedDark,
                  tooltip: 'Remove favourite',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              if (onDelete != null) const SizedBox(width: 2),
              Container(
                width: 25,
                height: 25,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: kMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
