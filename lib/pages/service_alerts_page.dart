import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/smart_move_widgets.dart';

class ServiceAlertsPage extends StatefulWidget {
  const ServiceAlertsPage({super.key});

  @override
  State<ServiceAlertsPage> createState() => _ServiceAlertsPageState();
}

class _ServiceAlertsPageState extends State<ServiceAlertsPage> {
  DateTime _lastChecked = DateTime.now();

  void _refresh() {
    setState(() => _lastChecked = DateTime.now());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Service alerts checked just now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final alerts = state.journeyAlertHistory;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(7, 0, 7, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(
                title: 'Service alerts',
                avatarLabel: avatarInitials(state.profileName),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: kInk,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Expanded(
                    child: PageTitle(
                      kicker: 'LIVE UPDATES',
                      title: 'Service alerts',
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    color: kTeal,
                    tooltip: 'Refresh alerts',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (alerts.isEmpty)
                const SoftCard(
                  color: kTealSoft,
                  padding: EdgeInsets.fromLTRB(13, 14, 13, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: kTeal,
                        size: 25,
                      ),
                      SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No recent journey alerts',
                              style: TextStyle(
                                fontSize: 13,
                                color: kInk,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Station arrival alerts will appear here when your next journey is active.',
                              style: TextStyle(fontSize: 10, color: kMutedDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                SectionHeading(
                  title: 'Recent journey alerts',
                  trailing: 'Clear',
                  onTrailingTap: state.clearJourneyAlertHistory,
                ),
                const SizedBox(height: 8),
                for (final alert in alerts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: SoftCard(
                      color: kYellow,
                      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.notifications_active_outlined,
                            color: Color(0xFFB08B2F),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  alert.message,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: kInk,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _dateTimeLabel(alert.occurredAt),
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    color: kMutedDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              SoftCard(
                color: kPeach,
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFB36F5C),
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Last checked ${_timeLabel(_lastChecked)}. Official disruption notices and journey alerts will appear here as they arrive.',
                        style: const TextStyle(fontSize: 9, color: kMutedDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeLabel(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _dateTimeLabel(DateTime time) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${time.day} ${months[time.month - 1]} · ${_timeLabel(time)}';
  }
}
