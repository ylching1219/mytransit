import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'pages/live_tracking_page.dart';
import 'pages/plan_page.dart';
import 'pages/profile_page.dart';
import 'pages/saved_page.dart';
import 'pages/service_alerts_page.dart';
import 'providers/app_state.dart';
import 'services/supabase_service.dart';
import 'services/transit_data_service.dart';
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
  bool _resumePromptScheduled = false;

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
    final state = context.watch<AppState>();
    if (state.shouldPromptResumeJourney && !_resumePromptScheduled) {
      _resumePromptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResumeJourneyDialog();
      });
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyTransitAssist',
      scaffoldMessengerKey: _messengerKey,
      themeMode: state.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: kBackground,
        colorScheme: ColorScheme.fromSeed(seedColor: kTeal),
        fontFamily: 'Arial',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101A1D),
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: kTeal,
              brightness: Brightness.dark,
            ).copyWith(
              primary: kTeal,
              surface: const Color(0xFF19282C),
              onSurface: Colors.white,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101A1D),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF19282C),
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF19282C)),
        dividerTheme: const DividerThemeData(color: Color(0xFF304247)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF24363A),
          labelStyle: const TextStyle(color: Color(0xFFAFC3C7)),
          floatingLabelStyle: const TextStyle(color: kTeal),
          hintStyle: const TextStyle(color: Color(0xFF8EA5AA)),
          prefixIconColor: const Color(0xFFB9CFD1),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4A6166)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kTeal, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF9C90)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF9C90), width: 1.6),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF26383D),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
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

  Future<void> _showResumeJourneyDialog() async {
    final state = context.read<AppState>();
    final route = state.nextRoute;
    if (route == null) return;

    final shouldContinue = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Continue your journey?'),
          content: Text(
            '${route.fromStopName} → ${route.toStopName}\n'
            'Depart ${TransitDataService.formatTime(route.departureTime)} · '
            'Arrive ${TransitDataService.formatTime(route.arrivalTime)}\n\n'
            'Your next journey was saved before the app closed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    final currentState = context.read<AppState>();
    final currentRoute = currentState.nextRoute;
    if (shouldContinue == true && currentRoute != null) {
      currentState.acknowledgeResumeJourneyPrompt();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LiveTrackingPage(route: currentRoute),
        ),
      );
    } else {
      currentState.clearNextRoute();
    }
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
