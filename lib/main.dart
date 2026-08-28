import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'pages/plan_page.dart';
import 'pages/profile_page.dart';
import 'pages/saved_page.dart';
import 'pages/service_alerts_page.dart';
import 'providers/app_state.dart';
import 'services/supabase_service.dart';
import 'widgets/smart_move_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.initialize();
  await SupabaseService().initialize();
  await appState.syncCloudData();
  runApp(
    ChangeNotifierProvider.value(value: appState, child: const SmartMoveApp()),
  );
}

class SmartMoveApp extends StatefulWidget {
  const SmartMoveApp({super.key});

  @override
  State<SmartMoveApp> createState() => _SmartMoveAppState();
}

class _SmartMoveAppState extends State<SmartMoveApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  AppState? _observedState;
  String? _lastShownJourneyAlert;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (_observedState == state) return;
    _observedState?.removeListener(_onAppStateChanged);
    _observedState = state;
    state.addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() {
    final state = _observedState;
    final alert = state?.journeyAlert;
    if (state == null || alert == null) {
      _lastShownJourneyAlert = null;
      return;
    }
    if (alert == _lastShownJourneyAlert) return;
    _lastShownJourneyAlert = alert;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = _messengerKey.currentState;
      if (messenger == null) {
        _lastShownJourneyAlert = null;
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(alert),
            backgroundColor: kInk,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      state.clearJourneyAlert();
    });
  }

  @override
  void dispose() {
    _observedState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyTransitAssist',
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBackground,
        colorScheme: ColorScheme.fromSeed(seedColor: kTeal),
        fontFamily: 'Arial',
      ),
      builder: (context, child) {
        final mediaQuery = MediaQuery.maybeOf(context);
        if (mediaQuery == null) return child ?? const SizedBox.shrink();
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SmartMoveShell(),
    );
  }
}

class SmartMoveShell extends StatelessWidget {
  const SmartMoveShell({super.key});

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: kInk,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: state.selectedIndex,
          children: [
            HomePage(
              onPlanTap: () => state.selectTab(1),
              onSavedTap: () => state.selectTab(2),
              onHistoryTap: () => state.selectTab(2),
              onAlertsTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ServiceAlertsPage()),
                );
              },
              onMessage: (message) => _showMessage(context, message),
            ),
            PlanPage(onMessage: (message) => _showMessage(context, message)),
            SavedPage(onMessage: (message) => _showMessage(context, message)),
            const ProfilePage(),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: state.selectedIndex,
        onSelected: state.selectTab,
      ),
    );
  }
}
