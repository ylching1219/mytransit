import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static const _channelId = 'journey_alerts';
  static const _channelName = 'Journey alerts';
  static const _channelDescription =
      'Station arrival and journey progress notifications.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextNotificationId = 1;

  Future<void> initialize() async {
    if (kIsWeb) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    try {
      await _plugin.initialize(settings: settings);
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> requestPermission() async {
    if (!_initialized || kIsWeb) return;

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // In-app alerts and alert history still work if permission is denied.
    }
  }

  Future<void> showJourneyAlert(String message) async {
    if (!_initialized || kIsWeb) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Journey alert',
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _plugin.show(
        id: _nextNotificationId++,
        title: 'MyTransitAssist journey alert',
        body: message,
        notificationDetails: details,
      );
    } catch (_) {
    }
  }
}
