import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'pages/plan_page.dart';
import 'pages/profile_page.dart';
import 'pages/saved_page.dart';
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

class SmartMoveApp extends StatelessWidget {
  const SmartMoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyTransitAssist',
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
