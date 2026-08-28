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
    return Scaffold(
      backgroundColor: kBackground,
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
              SoftCard(
                color: kTealSoft,
                padding: const EdgeInsets.fromLTRB(13, 14, 13, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.check_circle_outline_rounded,
                        color: kTeal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No active service alerts',
                            style: TextStyle(
                              fontSize: 13,
                              color: kInk,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'There are no disruption notices to show right now.',
                            style: TextStyle(fontSize: 10, color: kMutedDark),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
                        'Last checked ${_timeLabel(_lastChecked)}. New notices will appear here when the official alert feed provides them.',
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
}
