import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transit_models.dart';
import '../providers/app_state.dart';
import '../widgets/smart_move_widgets.dart';
import 'auth_page.dart';
import 'route_results_page.dart';

class SavedPage extends StatefulWidget {
  final ValueChanged<String> onMessage;

  const SavedPage({required this.onMessage, super.key});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  bool _showAllFavorites = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final visibleFavorites = _showAllFavorites
        ? state.savedPlaces
        : state.savedPlaces.take(3);
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
              onTap: () => widget.onMessage('More saved options'),
              child: Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
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
                state.selectTab(1);
              }
            },
          ),
          const SizedBox(height: 8),
          if (state.isGuest)
            SizedBox(
              width: double.infinity,
              child: SoftCard(
                color: appCardColor(context, kPurpleSoft),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: kPurple,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Guest mode cannot save favourite routes. Sign in to unlock this feature.',
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (state.savedPlaces.isEmpty)
            SizedBox(
              width: double.infinity,
              child: SoftCard(
                color: appCardColor(context, Colors.white),
                child: Text(
                  'No favourite routes yet. Save one from the Plan page.',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...visibleFavorites.map(
              (place) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Dismissible(
                  key: ValueKey(place.id),
                  direction: DismissDirection.endToStart,
                  background: const _SwipeRemoveBackground(),
                  confirmDismiss: (_) =>
                      _confirmRemoveFavoriteDialog(context, place),
                  onDismissed: (_) => _removeFavorite(context, place),
                  child: SavedItem(
                    icon: Icons.bookmark_outline_rounded,
                    iconBackground: kPurpleSoft,
                    eyebrow: 'FAVOURITE ROUTE',
                    title: place.title,
                    subtitle: place.subtitle,
                    onTap: () {
                      final locations = _splitRoute(place.title);
                      if (locations == null) {
                        widget.onMessage(
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
            ),
          if (!state.isGuest && state.savedPlaces.length > 3) ...[
            const SizedBox(height: 2),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() => _showAllFavorites = !_showAllFavorites);
                },
                icon: Icon(
                  _showAllFavorites
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                ),
                label: Text(
                  _showAllFavorites
                      ? 'Show fewer favourite routes'
                      : 'View all favourite routes (${state.savedPlaces.length})',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPurple,
                  side: BorderSide(color: kPurple.withValues(alpha: .45)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
          ],
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
            SizedBox(
              width: double.infinity,
              child: SoftCard(
                color: appCardColor(context, Colors.white),
                child: Text(
                  'Your completed journeys will appear here.',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
    widget.onMessage('Finding routes from $from to $to...');
    final found = await state.planJourney(from: from, to: to);
    if (!context.mounted) return;
    if (!found) {
      widget.onMessage(
        state.transitError ?? 'No route was found for this journey.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RouteResultsPage(from: from, to: to, departureTimeLabel: null),
      ),
    );
  }

  Future<bool> _confirmRemoveFavoriteDialog(
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
    return remove == true;
  }

  Future<void> _removeFavorite(BuildContext context, SavedPlace place) async {
    final removed = await context.read<AppState>().removeFavoriteRoute(
      place.id,
    );
    if (context.mounted && removed) {
      widget.onMessage('Favourite route removed');
    }
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

class SavedItem extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final String? eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SavedItem({
    required this.icon,
    required this.iconBackground,
    this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: SoftCard(
          color: appCardColor(context, Colors.white),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: appCardColor(context, iconBackground),
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
                        style: TextStyle(
                          fontSize: 7,
                          letterSpacing: .65,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    if (eyebrow != null) const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 25,
                height: 25,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: appCardColor(context, kBackground),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
