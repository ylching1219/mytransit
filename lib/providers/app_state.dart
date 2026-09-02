import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/transit_models.dart';
import '../services/database_adapter.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/realtime_transit_service.dart';
import '../services/supabase_service.dart';
import '../services/transit_data_service.dart';

class JourneyAlertRecord {
  final String message;
  final DateTime occurredAt;

  const JourneyAlertRecord({required this.message, required this.occurredAt});
}

class _BusMatchState {
  double? previousDistanceToBoarding;
  int consecutiveMatches = 0;
}

class AppState extends ChangeNotifier {
  static const _nextJourneyStorageKey = 'next_journey';

  final DatabaseAdapter _database = createDatabaseAdapter();
  final SupabaseService _supabaseService = SupabaseService();
  final LocationService _locationService = createLocationService();
  final NotificationService _notificationService = NotificationService();
  final RealtimeTransitService _realtimeTransitService =
      RealtimeTransitService();
  final TransitDataService _transitDataService = TransitDataService();
  final Uuid _uuid = const Uuid();

  SharedPreferences? _preferences;
  int _selectedIndex = 0;
  bool _isGuest = true;
  bool _isSearching = false;
  bool _notificationsEnabled = true;
  bool _darkMode = false;
  bool _gpsEnabled = false;
  bool _permissionGranted = false;
  bool _trackingEnabled = false;
  String? _transitError;
  TransitRouteResult? _lastRoute;
  TransitRouteResult? _nextRoute;
  String? _journeyAlert;
  int? _journeyRemainingStations;
  bool _journeyArrived = false;
  bool _journeyMonitoring = false;
  bool _journeyHasLocation = false;
  bool _resumeNextJourneyPrompt = false;
  int _lastReachedStationIndex = -1;
  bool _journeyLocationRequestInFlight = false;
  Timer? _journeyPollingTimer;
  Timer? _realtimeTransitTimer;
  bool _liveTransitLoading = false;
  DateTime? _liveTransitUpdatedAt;
  String? _liveTransitError;
  List<RealtimeTransitVehicle> _liveTransitVehicles = const [];
  RealtimeTransitVehicle? _assignedBus;
  String? _busDetectionStatus;
  bool _boardingStopValidated = false;
  LocationSnapshot? _latestJourneyLocation;
  final Map<String, _BusMatchState> _busMatchStates = {};
  List<TransitRouteResult> _routeOptions = const [];
  String _profileName = 'Guest';
  String _profileEmail = '';
  String _preferredTransport = 'Bus, rail & walking';
  List<SavedPlace> _savedPlaces = const [];
  List<JourneyRecord> _recentJourneys = const [];
  List<LocationSnapshot> _locationHistory = const [];
  List<JourneyAlertRecord> _journeyAlertHistory = const [];

  int get selectedIndex => _selectedIndex;
  bool get isGuest => _isGuest;
  bool get isSearching => _isSearching;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get darkMode => _darkMode;
  bool get gpsEnabled => _gpsEnabled;
  bool get permissionGranted => _permissionGranted;
  bool get trackingEnabled => _trackingEnabled;
  String? get transitError => _transitError;
  TransitRouteResult? get lastRoute => _lastRoute;
  TransitRouteResult? get nextRoute => _nextRoute;
  String? get journeyAlert => _journeyAlert;
  int? get journeyRemainingStations => _journeyRemainingStations;
  bool get journeyArrived => _journeyArrived;
  bool get journeyMonitoring => _journeyMonitoring;
  bool get journeyHasLocation => _journeyHasLocation;
  bool get shouldPromptResumeJourney => _resumeNextJourneyPrompt;
  List<TransitRouteResult> get routeOptions =>
      List.unmodifiable(_routeOptions.where(_matchesPreferredTransport));
  String get profileName => _profileName;
  String get profileEmail => _profileEmail;
  String get preferredTransport => _preferredTransport;
  List<SavedPlace> get savedPlaces => List.unmodifiable(_savedPlaces);
  List<JourneyRecord> get recentJourneys => List.unmodifiable(_recentJourneys);
  List<LocationSnapshot> get locationHistory =>
      List.unmodifiable(_locationHistory);
  List<JourneyAlertRecord> get journeyAlertHistory =>
      List.unmodifiable(_journeyAlertHistory);
  List<RealtimeTransitVehicle> get liveTransitVehicles =>
      List.unmodifiable(_liveTransitVehicles);
  DateTime? get liveTransitUpdatedAt => _liveTransitUpdatedAt;
  bool get liveTransitLoading => _liveTransitLoading;
  String? get liveTransitError => _liveTransitError;
  RealtimeTransitVehicle? get assignedBus => _assignedBus;
  String? get busDetectionStatus => _busDetectionStatus;
  bool get supabaseConfigured => _supabaseService.isConfigured;

  Future<void> initialize() async {
    await _notificationService.initialize();
    await _database.init();
    _preferences = await SharedPreferences.getInstance();
    final savedNextJourney = _preferences!.getString(_nextJourneyStorageKey);
    if (savedNextJourney != null) {
      final restoredRoute = _routeFromJson(savedNextJourney);
      if (restoredRoute == null) {
        await _preferences!.remove(_nextJourneyStorageKey);
      } else {
        _nextRoute = restoredRoute;
        _resumeNextJourneyPrompt = true;
      }
    }
    _isGuest = !(_preferences!.getBool('auth_signed_in') ?? false);
    _profileEmail = _isGuest
        ? ''
        : _preferences!.getString('profile_email') ?? '';
    _profileName = _isGuest ? 'Guest' : _profileNameForEmail(_profileEmail);
    _loadTravelPreferences();
    _notificationsEnabled =
        _preferences!.getBool('notifications_enabled') ?? true;
    _darkMode = _preferences!.getBool('dark_mode') ?? false;
    _database.setUserScope(
      _isGuest ? 'guest' : _storageScopeForEmail(_profileEmail),
    );
    _savedPlaces = _isGuest ? const [] : await _database.loadSavedPlaces();
    final loadedJourneys = _isGuest
        ? const <JourneyRecord>[]
        : await _database.loadJourneys();
    _recentJourneys = _limitRecentJourneys(loadedJourneys);
    if (_recentJourneys.length != loadedJourneys.length) {
      await _database.saveJourneys(_recentJourneys);
    }

    final status = await _locationService.checkStatus();
    _gpsEnabled = status.gpsEnabled;
    _permissionGranted = status.permissionGranted;
    notifyListeners();
  }

  void selectTab(int index) {
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    notifyListeners();
  }

  void markNextRoute(TransitRouteResult route) {
    _nextRoute = route;
    _resumeNextJourneyPrompt = false;
    _journeyAlert = null;
    _journeyRemainingStations = null;
    _journeyArrived = false;
    _journeyHasLocation = false;
    _lastReachedStationIndex = -1;
    _resetBusAssignment();
    unawaited(_persistNextRoute(route));
    notifyListeners();
    if (_notificationsEnabled) unawaited(_restartJourneyMonitoring());
  }

  void clearNextRoute() {
    if (_nextRoute == null && !_resumeNextJourneyPrompt) return;
    _nextRoute = null;
    _resumeNextJourneyPrompt = false;
    _journeyAlert = null;
    _journeyRemainingStations = null;
    _journeyArrived = false;
    _journeyHasLocation = false;
    _lastReachedStationIndex = -1;
    _resetBusAssignment();
    unawaited(_removePersistedNextRoute());
    unawaited(stopJourneyMonitoring());
    notifyListeners();
  }

  bool isNextRoute(TransitRouteResult route) {
    final selected = _nextRoute;
    if (selected == null) return false;
    return selected.fromStopId == route.fromStopId &&
        selected.toStopId == route.toStopId &&
        selected.serviceName == route.serviceName &&
        selected.departureTime == route.departureTime;
  }

  void acknowledgeResumeJourneyPrompt() {
    if (!_resumeNextJourneyPrompt) return;
    _resumeNextJourneyPrompt = false;
    notifyListeners();
  }

  void requestResumeJourneyPrompt() {
    if (_nextRoute == null || _resumeNextJourneyPrompt) return;
    _resumeNextJourneyPrompt = true;
    notifyListeners();
  }

  Future<bool> planJourney({
    required String from,
    required String to,
    int? departureAfterSeconds,
    int? departureBeforeSeconds,
  }) async {
    if (from.trim().isEmpty || to.trim().isEmpty) return false;
    _isSearching = true;
    _transitError = null;
    _lastRoute = null;
    _routeOptions = const [];
    notifyListeners();
    try {
      final allRoutes = await _transitDataService.findRoutes(
        from: from,
        to: to,
        departureAfterSeconds: departureAfterSeconds,
        departureBeforeSeconds: departureBeforeSeconds,
      );
      if (allRoutes.isEmpty) {
        _transitError = 'No direct route was found for these stops.';
        return false;
      }

      final routes = allRoutes
          .where(_matchesPreferredTransport)
          .toList(growable: false);
      if (routes.isEmpty) {
        _transitError =
            'No ${_preferredTransport.toLowerCase()} route was found for this journey.';
        return false;
      }

      _routeOptions = routes;
      final route = routes.first;
      _lastRoute = route;
      return true;
    } catch (error) {
      _transitError = error is TransitDataException
          ? error.message
          : 'Could not load government transit data.';
      return false;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void resetJourneySearch() {
    _transitError = null;
    _lastRoute = null;
    _routeOptions = const [];
    notifyListeners();
  }

  Future<bool> saveFavoriteRoute({
    required String from,
    required String to,
  }) async {
    final cleanFrom = from.trim();
    final cleanTo = to.trim();
    if (_isGuest || cleanFrom.isEmpty || cleanTo.isEmpty) return false;
    if (isFavoriteRouteSaved(from: cleanFrom, to: cleanTo)) return false;
    final place = SavedPlace(
      id: _uuid.v4(),
      title: '$cleanFrom → $cleanTo',
      subtitle: 'LRT Kelana Jaya · Saved route',
    );
    _savedPlaces = [place, ..._savedPlaces].take(20).toList();
    await _database.saveSavedPlaces(_savedPlaces);
    await _syncSavedPlacesToCloud();
    notifyListeners();
    return true;
  }

  bool isFavoriteRouteSaved({required String from, required String to}) {
    final cleanFrom = from.trim();
    final cleanTo = to.trim();
    if (cleanFrom.isEmpty || cleanTo.isEmpty) return false;
    final routeTitle = _normaliseFavoriteText('$cleanFrom → $cleanTo');
    return _savedPlaces.any(
      (place) => _normaliseFavoriteText(place.title) == routeTitle,
    );
  }

  Future<bool> removeFavoriteRoute(String id) async {
    if (_isGuest) return false;
    final updated = _savedPlaces.where((place) => place.id != id).toList();
    if (updated.length == _savedPlaces.length) return false;
    _savedPlaces = updated;
    await _database.saveSavedPlaces(_savedPlaces);
    await _syncSavedPlacesToCloud();
    notifyListeners();
    return true;
  }

  Future<void> clearFavoriteRoutes() async {
    if (_isGuest || _savedPlaces.isEmpty) return;
    _savedPlaces = const [];
    await _database.saveSavedPlaces(_savedPlaces);
    await _syncSavedPlacesToCloud();
    notifyListeners();
  }

  Future<bool> markNextJourneyDone() async {
    final route = _nextRoute;
    if (route == null || !_journeyArrived) return false;

    final journey = JourneyRecord(
      id: _uuid.v4(),
      from: route.fromStopName,
      to: route.toStopName,
      service: route.serviceName,
      durationMinutes: route.durationMinutes,
      createdAt: DateTime.now(),
    );
    _recentJourneys = _limitRecentJourneys([journey, ..._recentJourneys]);
    await _database.saveJourneys(_recentJourneys);
    await _syncJourneysToCloud();

    _nextRoute = null;
    _resumeNextJourneyPrompt = false;
    _journeyAlert = null;
    _journeyRemainingStations = null;
    _journeyArrived = false;
    _journeyHasLocation = false;
    _lastReachedStationIndex = -1;
    _resetBusAssignment();
    await _removePersistedNextRoute();
    await stopJourneyMonitoring();
    notifyListeners();
    return true;
  }

  Future<void> signIn({required String email, required String password}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || password.isEmpty) {
      throw const FormatException('Enter your email and password.');
    }

    if (_supabaseService.isConfigured) {
      await _supabaseService.signIn(email: cleanEmail, password: password);
    } else {
      final storedEmail = _preferences?.getString('account_email');
      final storedPassword = _preferences?.getString('account_password');
      if (storedEmail != cleanEmail || storedPassword != password) {
        throw const FormatException('Email or password is incorrect.');
      }
    }
    await _activateAccount(
      name: _profileNameForEmail(cleanEmail),
      email: cleanEmail,
    );
    await syncCloudData();
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanName.isEmpty || cleanEmail.isEmpty || password.length < 6) {
      throw const FormatException(
        'Enter a name, a valid email, and a password of at least 6 characters.',
      );
    }

    if (!_supabaseService.isConfigured &&
        _preferences?.getString('account_email') == cleanEmail) {
      throw const FormatException(
        'This email is already registered. Please log in instead.',
      );
    }

    if (_supabaseService.isConfigured) {
      final hasSession = await _supabaseService.signUp(
        name: cleanName,
        email: cleanEmail,
        password: password,
      );
      if (!hasSession) {
        throw const FormatException(
          'Account created. Verify your email, then sign in.',
        );
      }
    } else {
      await _preferences?.setString('account_name', cleanName);
      await _preferences?.setString('account_email', cleanEmail);
      await _preferences?.setString('account_password', password);
    }
    await _activateAccount(name: cleanName, email: cleanEmail);
    await syncCloudData();
  }

  Future<void> _activateAccount({
    required String name,
    required String email,
  }) async {
    _isGuest = false;
    _profileName = name;
    _profileEmail = email;
    _loadTravelPreferences();
    _database.setUserScope(_storageScopeForEmail(email));
    _savedPlaces = await _database.loadSavedPlaces();
    final loadedJourneys = await _database.loadJourneys();
    _recentJourneys = _limitRecentJourneys(loadedJourneys);
    if (_recentJourneys.length != loadedJourneys.length) {
      await _database.saveJourneys(_recentJourneys);
    }
    await _preferences?.setBool('auth_signed_in', true);
    await _preferences?.setString('profile_name', name);
    await _preferences?.setString('profile_email', email);
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_supabaseService.isConfigured) await _supabaseService.signOut();
    _isGuest = true;
    _profileName = 'Guest';
    _profileEmail = '';
    _loadTravelPreferences();
    _savedPlaces = const [];
    _recentJourneys = const [];
    _lastRoute = null;
    _routeOptions = const [];
    _database.setUserScope('guest');
    _nextRoute = null;
    _resumeNextJourneyPrompt = false;
    _journeyAlert = null;
    _journeyRemainingStations = null;
    _journeyArrived = false;
    _journeyHasLocation = false;
    _lastReachedStationIndex = -1;
    _resetBusAssignment();
    _journeyAlertHistory = const [];
    unawaited(_removePersistedNextRoute());
    await stopJourneyMonitoring();
    await _preferences?.setBool('auth_signed_in', false);
    notifyListeners();
  }

  String _storageScopeForEmail(String email) {
    return email.trim().toLowerCase();
  }

  String _profileNameForEmail(String email) {
    final storedName = _preferences?.getString('profile_name')?.trim();
    if (storedName != null &&
        storedName.isNotEmpty &&
        storedName != 'Aina Koh') {
      return storedName;
    }
    final accountName = _preferences?.getString('account_name')?.trim();
    if (accountName != null &&
        accountName.isNotEmpty &&
        accountName != 'Aina Koh') {
      return accountName;
    }
    final emailName = email.trim().split('@').first.trim();
    return emailName.isEmpty ? 'User' : emailName;
  }

  void _loadTravelPreferences() {
    const defaultTransport = 'Bus, rail & walking';
    if (_isGuest) {
      _preferredTransport = defaultTransport;
      return;
    }
    const supportedTransports = {
      defaultTransport,
      'Rail + walking',
      'Bus + walking',
    };
    final scope = _storageScopeForEmail(_profileEmail);
    final storedTransport = _preferences?.getString('travel_transport_$scope');
    _preferredTransport = supportedTransports.contains(storedTransport)
        ? storedTransport!
        : defaultTransport;
  }

  Future<void> updatePreferredTransport(String preferredTransport) async {
    if (_isGuest) return;
    _preferredTransport = preferredTransport;
    final scope = _storageScopeForEmail(_profileEmail);
    await _preferences?.setString(
      'travel_transport_$scope',
      _preferredTransport,
    );
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    _darkMode = enabled;
    await _preferences?.setBool('dark_mode', enabled);
    notifyListeners();
  }

  bool _matchesPreferredTransport(TransitRouteResult route) {
    if (_isGuest) return true;
    if (_preferredTransport == 'Bus, rail & walking') return true;

    final modeNames = [
      route.mode,
      ...route.legs.map((leg) => leg.mode),
    ].join(' ').toLowerCase();
    final hasBus = modeNames.contains('bus');
    final hasRail = RegExp(r'\b(lrt|mrt|rail|train)\b').hasMatch(modeNames);

    switch (_preferredTransport) {
      case 'Rail + walking':
        return hasRail && !hasBus;
      case 'Bus + walking':
        return hasBus && !hasRail;
      default:
        return true;
    }
  }

  Future<void> setNotifications(bool enabled) async {
    _notificationsEnabled = enabled;
    await _preferences?.setBool('notifications_enabled', enabled);
    if (!enabled) {
      await stopJourneyMonitoring();
      _journeyAlert = null;
      _journeyRemainingStations = null;
      _journeyArrived = false;
      _journeyHasLocation = false;
      _lastReachedStationIndex = -1;
    } else {
      await _notificationService.requestPermission();
      if (_nextRoute != null) {
        unawaited(_restartJourneyMonitoring());
      }
    }
    notifyListeners();
  }

  Future<void> saveProfile({
    required String name,
    required String email,
  }) async {
    _profileName = name.trim();
    _profileEmail = email.trim();
    await _preferences?.setString('profile_name', _profileName);
    await _preferences?.setString('profile_email', _profileEmail);
    if (!_isGuest) {
      await _preferences?.setString('account_name', _profileName);
    }
    notifyListeners();
  }

  Future<void> syncProfile() async {
    await _supabaseService.syncProfile(
      name: _profileName,
      email: _profileEmail,
    );
  }

  Future<void> syncCloudData() async {
    if (_isGuest || !_supabaseService.isConfigured) return;

    try {
      final remotePlaces = await _supabaseService.loadSavedPlaces();
      if (remotePlaces.isEmpty && _savedPlaces.isNotEmpty) {
        await _supabaseService.saveSavedPlaces(_savedPlaces);
      } else {
        _savedPlaces = remotePlaces;
        await _database.saveSavedPlaces(_savedPlaces);
      }
    } catch (_) {
      // Keep the local cache available when Supabase is offline or not ready.
    }

    try {
      final remoteJourneys = await _supabaseService.loadJourneys();
      if (remoteJourneys.isEmpty && _recentJourneys.isNotEmpty) {
        _recentJourneys = _limitRecentJourneys(_recentJourneys);
        await _supabaseService.saveJourneys(_recentJourneys);
      } else {
        _recentJourneys = _limitRecentJourneys(remoteJourneys);
        await _database.saveJourneys(_recentJourneys);
        if (_recentJourneys.length != remoteJourneys.length) {
          await _supabaseService.saveJourneys(_recentJourneys);
        }
      }
    } catch (_) {
      // Keep the local cache available when Supabase is offline or not ready.
    }
    notifyListeners();
  }

  Future<void> _syncSavedPlacesToCloud() async {
    if (_isGuest || !_supabaseService.isConfigured) return;
    try {
      await _supabaseService.saveSavedPlaces(_savedPlaces);
    } catch (_) {
      // The local database remains the offline source of truth.
    }
  }

  Future<void> _syncJourneysToCloud() async {
    if (_isGuest || !_supabaseService.isConfigured) return;
    try {
      await _supabaseService.saveJourneys(_recentJourneys);
    } catch (_) {
      // The local database remains the offline source of truth.
    }
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_isGuest) {
      throw const FormatException('Sign in before changing your password.');
    }
    if (currentPassword.isEmpty) {
      throw const FormatException('Enter your current password.');
    }
    if (newPassword.length < 6) {
      throw const FormatException('Use at least 6 characters.');
    }
    if (_supabaseService.isConfigured) {
      await _supabaseService.updatePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return;
    }
    final storedPassword = _preferences?.getString('account_password');
    if (storedPassword != currentPassword) {
      throw const FormatException('Current password is incorrect.');
    }
    await _preferences?.setString('account_password', newPassword);
  }

  Future<void> clearJourneys() async {
    _recentJourneys = const [];
    await _database.saveJourneys(_recentJourneys);
    await _syncJourneysToCloud();
    notifyListeners();
  }

  List<JourneyRecord> _limitRecentJourneys(Iterable<JourneyRecord> journeys) {
    return journeys.take(6).toList(growable: false);
  }

  String _normaliseFavoriteText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> requestGps() async {
    _gpsEnabled = await _locationService.requestGps();
    notifyListeners();
  }

  Future<void> requestLocationPermission() async {
    _permissionGranted = await _locationService.requestPermission();
    notifyListeners();
  }

  Future<LocationSnapshot?> getCurrentLocation() async {
    if (!_permissionGranted) await requestLocationPermission();
    if (!_gpsEnabled) await requestGps();
    if (!_permissionGranted || !_gpsEnabled) return null;

    final snapshot = await _locationService.getCurrentLocation();
    if (snapshot.latitude == null || snapshot.longitude == null) return null;
    _locationHistory = [snapshot, ..._locationHistory].take(20).toList();
    notifyListeners();
    return snapshot;
  }

  Future<List<NearbyTransitStop>> findNearbyTransitStops({
    required double latitude,
    required double longitude,
    double maxDistanceMeters = 1500,
    int limit = 8,
  }) {
    return _transitDataService.findNearbyStops(
      latitude: latitude,
      longitude: longitude,
      maxDistanceMeters: maxDistanceMeters,
      limit: limit,
    );
  }

  Future<List<TransitPlaceSuggestion>> searchTransitSuggestions({
    required String query,
  }) {
    return _transitDataService.searchPlaceSuggestions(query: query);
  }

  void clearJourneyAlert() {
    if (_journeyAlert == null) return;
    _journeyAlert = null;
    notifyListeners();
  }

  Future<void> startJourneyMonitoring() async {
    if (_nextRoute == null) return;
    unawaited(startRealtimeTransitMonitoring());
    if (!_notificationsEnabled || _journeyMonitoring) return;

    if (!_permissionGranted) {
      _permissionGranted = await _locationService.requestPermission();
    }
    if (!_gpsEnabled) {
      _gpsEnabled = await _locationService.requestGps();
    }
    if (!_permissionGranted || !_gpsEnabled) {
      _publishJourneyAlert(
        'Allow location access to receive station arrival alerts.',
      );
      notifyListeners();
      return;
    }

    try {
      await _notificationService.requestPermission();
      final initialLocation = await _locationService.getCurrentLocation();
      _handleJourneyLocation(initialLocation);
      if (_journeyArrived || _nextRoute == null) return;

      _journeyPollingTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_pollJourneyLocation()),
      );
      if (!kIsWeb) {
        await _locationService.startTracking(_handleJourneyLocation);
      }
      _journeyMonitoring = true;
      notifyListeners();
    } catch (_) {
      _publishJourneyAlert('Could not start location alerts for this journey.');
      notifyListeners();
    }
  }

  Future<void> stopJourneyMonitoring() async {
    _journeyPollingTimer?.cancel();
    _journeyPollingTimer = null;
    stopRealtimeTransitMonitoring();
    await _locationService.stopTracking();
    if (!_journeyMonitoring) return;
    _journeyMonitoring = false;
    notifyListeners();
  }

  Future<void> _restartJourneyMonitoring() async {
    await stopJourneyMonitoring();
    if (_nextRoute != null && _notificationsEnabled) {
      await startJourneyMonitoring();
    }
  }

  Future<void> _pollJourneyLocation() async {
    if (_journeyLocationRequestInFlight || _nextRoute == null) return;
    _journeyLocationRequestInFlight = true;
    try {
      final snapshot = await _locationService.getCurrentLocation();
      _handleJourneyLocation(snapshot);
    } catch (_) {
      // Keep the last known progress when a single location read fails.
    } finally {
      _journeyLocationRequestInFlight = false;
    }
  }

  Future<void> startRealtimeTransitMonitoring() async {
    if (_nextRoute == null || _realtimeTransitTimer != null) return;
    await refreshLiveTransitData();
    if (_nextRoute == null) return;
    _realtimeTransitTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refreshLiveTransitData()),
    );
    notifyListeners();
  }

  void stopRealtimeTransitMonitoring() {
    _realtimeTransitTimer?.cancel();
    _realtimeTransitTimer = null;
  }

  Future<void> refreshLiveTransitData() async {
    final route = _nextRoute;
    if (route == null || _liveTransitLoading) return;
    _liveTransitLoading = true;
    _liveTransitError = null;
    notifyListeners();
    try {
      final mappedRouteIds = await _transitDataService.realtimeBusRouteIdsFor(
        route,
      );
      final busStopLookup = await _transitDataService
          .realtimeBusStopLookupForRoutes(mappedRouteIds);
      final snapshot = await _realtimeTransitService.fetchForRoute(
        route,
        mappedRouteIds: mappedRouteIds,
        busStopLookup: busStopLookup,
      );
      if (_nextRoute == route) {
        _liveTransitUpdatedAt = snapshot.fetchedAt;
        _liveTransitError = snapshot.errorMessage;
        _updateAutomaticBusAssignment(route, snapshot.vehicles);
        final assignedBusId = _assignedBus?.id;
        RealtimeTransitVehicle? trackedVehicle;
        if (assignedBusId != null) {
          for (final vehicle in snapshot.vehicles) {
            if (_sameVehicleId(vehicle.id, assignedBusId)) {
              trackedVehicle = vehicle;
              break;
            }
          }
        }
        if (trackedVehicle != null) {
          _updateJourneyProgress(
            LocationSnapshot(
              latitude: trackedVehicle.latitude,
              longitude: trackedVehicle.longitude,
            ),
          );
        }
        if (assignedBusId == null) {
          _liveTransitVehicles = snapshot.vehicles;
        } else {
          _liveTransitVehicles = snapshot.vehicles
              .where((vehicle) => _sameVehicleId(vehicle.id, assignedBusId))
              .toList(growable: false);
        }
      }
    } catch (_) {
      if (_nextRoute == route) {
        // Keep the status card honest even when the request itself fails:
        // this is the last time the app checked the live feed, not an old
        // timestamp left over from a previous journey.
        _liveTransitUpdatedAt = DateTime.now().toUtc();
        _liveTransitError = 'Live transit data is temporarily unavailable.';
      }
    } finally {
      _liveTransitLoading = false;
      notifyListeners();
    }
  }

  void _handleJourneyLocation(LocationSnapshot snapshot) {
    if (_nextRoute == null ||
        snapshot.latitude == null ||
        snapshot.longitude == null) {
      return;
    }
    _latestJourneyLocation = snapshot;
    _locationHistory = [snapshot, ..._locationHistory].take(20).toList();
    _journeyHasLocation = true;
    _updateJourneyProgress(snapshot);
    final route = _nextRoute;
    if (route != null) {
      _updateAutomaticBusAssignment(route, _liveTransitVehicles);
      _keepOnlyAssignedBus();
    }
    notifyListeners();
  }

  void _updateJourneyProgress(LocationSnapshot snapshot) {
    final route = _nextRoute;
    if (route == null ||
        snapshot.latitude == null ||
        snapshot.longitude == null) {
      return;
    }
    final stations = _stationsForRoute(route);
    if (stations.isEmpty) return;

    var nearestIndex = -1;
    var nearestDistance = double.infinity;
    for (var index = 0; index < stations.length; index++) {
      final station = stations[index];
      final distance = _distanceMeters(
        snapshot.latitude!,
        snapshot.longitude!,
        station.latitude,
        station.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }

    // GPS can drift, so only announce a station when the user is within
    // 250 metres of it.
    if (nearestIndex < 0 || nearestDistance > 250) return;
    if (nearestIndex <= _lastReachedStationIndex) return;

    _lastReachedStationIndex = nearestIndex;
    final remaining = math.max(0, stations.length - nearestIndex - 1);
    _journeyRemainingStations = remaining;
    final stationName = stations[nearestIndex].name;
    final destinationName = stations.last.name;
    final nextService = _nextServiceChangeAtStation(
      route,
      stations[nearestIndex],
    );
    if (remaining == 0) {
      _journeyArrived = true;
      _publishJourneyAlert('Arrived at $destinationName.');
      unawaited(stopJourneyMonitoring());
    } else if (nextService != null) {
      _publishJourneyAlert(
        'Change service at $stationName. Take the $nextService service next.',
      );
    } else if (nearestIndex == 0) {
      _publishJourneyAlert(
        'Arrived at your first station, $stationName. $remaining stations remaining.',
      );
    } else if (remaining == 2) {
      _publishJourneyAlert('2 stations remaining until $destinationName.');
    } else {
      // Intermediate stations do not produce an alert.
    }
  }

  void _resetBusAssignment() {
    _assignedBus = null;
    _busDetectionStatus = null;
    _boardingStopValidated = false;
    _latestJourneyLocation = null;
    _busMatchStates.clear();
    _liveTransitVehicles = const [];
    _liveTransitUpdatedAt = null;
    _liveTransitError = null;
  }

  void _keepOnlyAssignedBus() {
    final assignedBus = _assignedBus;
    if (assignedBus == null) return;
    _liveTransitVehicles = _liveTransitVehicles
        .where((vehicle) => _sameVehicleId(vehicle.id, assignedBus.id))
        .toList(growable: false);
  }

  void _updateAutomaticBusAssignment(
    TransitRouteResult route,
    List<RealtimeTransitVehicle> vehicles,
  ) {
    final boardingLeg = _firstBusBoardingLeg(route);
    if (boardingLeg == null) return;

    final location = _latestJourneyLocation;
    if (location?.latitude == null || location?.longitude == null) {
      _busDetectionStatus = vehicles.isEmpty
          ? 'Waiting for live bus GPS data.'
          : '${vehicles.length} route bus${vehicles.length == 1 ? '' : 'es'} found. Allow location to match your bus.';
      return;
    }

    final assignedBus = _assignedBus;
    if (assignedBus != null) {
      RealtimeTransitVehicle? updatedBus;
      for (final vehicle in vehicles) {
        if (_sameVehicleId(vehicle.id, assignedBus.id)) {
          updatedBus = vehicle;
          break;
        }
      }
      if (updatedBus != null) {
        _assignedBus = updatedBus;
        _busDetectionStatus =
            'Bus ${_vehicleLabel(updatedBus)} matched. Live tracking is following it.';
      } else {
        _busDetectionStatus =
            'Tracking bus ${_vehicleLabel(assignedBus)}; waiting for its next live update.';
      }
      return;
    }

    final userLatitude = location!.latitude!;
    final userLongitude = location.longitude!;
    final boardingLatitude = boardingLeg.fromLatitude;
    final boardingLongitude = boardingLeg.fromLongitude;
    final userToBoarding = _distanceMeters(
      userLatitude,
      userLongitude,
      boardingLatitude,
      boardingLongitude,
    );
    const maxUserToBoardingMeters = 150.0;
    const maxVehicleToBoardingMeters = 500.0;
    const maxUserToVehicleMeters = 100.0;
    // Validate the boarding stop only once. The user is expected to leave the
    // stop after boarding, so this must not remain a permanent requirement.
    if (userToBoarding <= maxUserToBoardingMeters) {
      _boardingStopValidated = true;
    }
    if (!_boardingStopValidated) {
      _busDetectionStatus =
          'Move closer to ${boardingLeg.fromStopName} to identify your bus.';
      _busMatchStates.clear();
      return;
    }

    final candidates = <RealtimeTransitVehicle>[];
    final previousDistances = <String, double?>{};
    final candidateDistances = <String, double>{};

    for (final vehicle in vehicles) {
      if (vehicle.mode != 'Bus') continue;
      // RealtimeTransitService has already filtered vehicles using the
      // official static GTFS route mapping. Do not compare the planner's raw
      // routeId here because the two feeds can use different ID namespaces.

      final vehicleToBoarding = _distanceMeters(
        vehicle.latitude,
        vehicle.longitude,
        boardingLatitude,
        boardingLongitude,
      );
      final userToVehicle = _distanceMeters(
        userLatitude,
        userLongitude,
        vehicle.latitude,
        vehicle.longitude,
      );
      // Before the bus leaves, use the boarding-stop radius. Once the user
      // has been validated at that stop, a bus may be farther along the route;
      // the phone-to-bus radius becomes the useful safety check.
      if (vehicleToBoarding > maxVehicleToBoardingMeters &&
          userToVehicle > maxUserToVehicleMeters) {
        continue;
      }

      final key = _normaliseVehicleId(vehicle);
      final matchState = _busMatchStates.putIfAbsent(key, _BusMatchState.new);
      previousDistances[key] = matchState.previousDistanceToBoarding;
      candidateDistances[key] = vehicleToBoarding;
      candidates.add(vehicle);
    }

    if (candidates.isEmpty) {
      _busMatchStates.clear();
      _busDetectionStatus = vehicles.isEmpty
          ? 'Waiting for live bus GPS data near ${boardingLeg.fromStopName}.'
          : 'Waiting for a route bus near ${boardingLeg.fromStopName}.';
      return;
    }

    final userHasLeftBoardingStop = userToBoarding >= 80;
    if (!userHasLeftBoardingStop) {
      for (final vehicle in candidates) {
        final key = _normaliseVehicleId(vehicle);
        final matchState = _busMatchStates[key]!;
        matchState.consecutiveMatches = 0;
        matchState.previousDistanceToBoarding = candidateDistances[key];
      }
      _busDetectionStatus =
          'Bus detected near ${boardingLeg.fromStopName}. Waiting for it to leave the stop.';
      return;
    }

    RealtimeTransitVehicle? bestMatch;
    var bestDistanceToUser = double.infinity;
    var aBusIsMoving = false;
    for (final vehicle in candidates) {
      final key = _normaliseVehicleId(vehicle);
      final matchState = _busMatchStates[key]!;
      final vehicleToBoarding = candidateDistances[key]!;
      final previousDistance = previousDistances[key];
      final busHasMoved =
          vehicleToBoarding > 120 &&
          (previousDistance == null ||
              vehicleToBoarding > previousDistance + 15);
      aBusIsMoving = aBusIsMoving || busHasMoved;
      final userToVehicle = _distanceMeters(
        userLatitude,
        userLongitude,
        vehicle.latitude,
        vehicle.longitude,
      );
      if (busHasMoved && userToVehicle <= maxUserToVehicleMeters) {
        matchState.consecutiveMatches++;
        if (matchState.consecutiveMatches >= 1 &&
            userToVehicle < bestDistanceToUser) {
          bestMatch = vehicle;
          bestDistanceToUser = userToVehicle;
        }
      } else {
        matchState.consecutiveMatches = 0;
      }
      matchState.previousDistanceToBoarding = vehicleToBoarding;
    }

    if (bestMatch != null) {
      _assignedBus = bestMatch;
      _busDetectionStatus =
          'Bus ${_vehicleLabel(bestMatch)} matched. Live tracking is following it.';
      _busMatchStates.clear();
      return;
    }

    _busDetectionStatus = aBusIsMoving
        ? 'Bus moving near you. Matching your location…'
        : 'Bus detected near ${boardingLeg.fromStopName}. Waiting for it to leave the stop.';
  }

  TransitJourneyLeg? _firstBusBoardingLeg(TransitRouteResult route) {
    for (final leg in route.legs) {
      if (leg.mode == 'Bus') return leg;
    }
    if (route.mode != 'Bus') return null;
    return TransitJourneyLeg(
      mode: route.mode,
      serviceName: route.serviceName,
      fromStopName: route.fromStopName,
      toStopName: route.toStopName,
      fromStopId: route.fromStopId,
      toStopId: route.toStopId,
      departureTime: route.departureTime,
      arrivalTime: route.arrivalTime,
      fare: route.fare,
      durationMinutes: route.durationMinutes,
      stopsBetween: route.stopsBetween,
      fromLatitude: route.fromLatitude,
      fromLongitude: route.fromLongitude,
      toLatitude: route.toLatitude,
      toLongitude: route.toLongitude,
      routeId: route.routeId,
    );
  }

  static String _normaliseVehicleId(RealtimeTransitVehicle vehicle) {
    final id = vehicle.id.trim();
    return (id.isEmpty ? vehicle.label : id).trim().toLowerCase();
  }

  static bool _sameVehicleId(String first, String second) {
    return first.trim().toLowerCase() == second.trim().toLowerCase();
  }

  static String _vehicleLabel(RealtimeTransitVehicle vehicle) {
    final id = vehicle.id.trim();
    return id.isEmpty ? vehicle.label : id;
  }

  String? _nextServiceChangeAtStation(
    TransitRouteResult route,
    TransitStationPoint station,
  ) {
    final transitLegs = route.legs.where((leg) => !leg.isWalking).toList();
    for (var index = 0; index < transitLegs.length - 1; index++) {
      final currentLeg = transitLegs[index];
      final nextLeg = transitLegs[index + 1];
      final currentService = '${currentLeg.mode}:${currentLeg.serviceName}';
      final nextService = '${nextLeg.mode}:${nextLeg.serviceName}';
      if (currentService == nextService) continue;

      final transferId = currentLeg.toStopId.isNotEmpty
          ? currentLeg.toStopId
          : nextLeg.fromStopId;
      final sameId = transferId.isNotEmpty && station.id == transferId;
      final stationName = station.name.trim().toLowerCase();
      final sameName =
          stationName == currentLeg.toStopName.trim().toLowerCase() ||
          stationName == nextLeg.fromStopName.trim().toLowerCase();
      if (sameId || sameName) return nextLeg.serviceName;
    }
    return null;
  }

  void _publishJourneyAlert(String message) {
    _journeyAlert = message;
    _journeyAlertHistory = [
      JourneyAlertRecord(message: message, occurredAt: _malaysiaNow()),
      ..._journeyAlertHistory,
    ].take(20).toList();
    unawaited(_notificationService.showJourneyAlert(message));
  }

  void clearJourneyAlertHistory() {
    if (_journeyAlertHistory.isEmpty) return;
    _journeyAlertHistory = const [];
    notifyListeners();
  }

  DateTime _malaysiaNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  List<TransitStationPoint> _stationsForRoute(TransitRouteResult route) {
    final stations = <TransitStationPoint>[];
    final seen = <String>{};
    for (final leg in route.legs) {
      if (leg.isWalking) continue;
      for (final station in leg.passingStations) {
        final key = station.name.toLowerCase().trim();
        if (seen.add(key)) stations.add(station);
      }
    }
    if (stations.isNotEmpty) return stations;
    return [
      TransitStationPoint(
        id: route.fromStopId,
        name: route.fromStopName,
        latitude: route.fromLatitude,
        longitude: route.fromLongitude,
      ),
      TransitStationPoint(
        id: route.toStopId,
        name: route.toStopName,
        latitude: route.toLatitude,
        longitude: route.toLongitude,
      ),
    ];
  }

  static double _distanceMeters(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(latitudeB - latitudeA);
    final longitudeDelta = _radians(longitudeB - longitudeA);
    final a =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(_radians(latitudeA)) *
            math.cos(_radians(latitudeB)) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    final clamped = a.clamp(0.0, 1.0).toDouble();
    return earthRadiusMeters * 2 * math.asin(math.sqrt(clamped));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  Future<void> startLocationTracking() async {
    if (!_gpsEnabled || !_permissionGranted) return;
    await _locationService.startTracking((snapshot) {
      _locationHistory = [snapshot, ..._locationHistory].take(20).toList();
      notifyListeners();
    });
    _trackingEnabled = true;
    notifyListeners();
  }

  Future<void> stopLocationTracking() async {
    await _locationService.stopTracking();
    _trackingEnabled = false;
    _locationHistory = const [];
    notifyListeners();
  }

  Future<void> _persistNextRoute(TransitRouteResult route) async {
    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.setString(
      _nextJourneyStorageKey,
      jsonEncode(_routeToJson(route)),
    );
  }

  Future<void> _removePersistedNextRoute() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.remove(_nextJourneyStorageKey);
  }

  Map<String, dynamic> _routeToJson(TransitRouteResult route) {
    return {
      'fromStopName': route.fromStopName,
      'toStopName': route.toStopName,
      'fromStopId': route.fromStopId,
      'toStopId': route.toStopId,
      'serviceName': route.serviceName,
      'mode': route.mode,
      'departureTime': route.departureTime,
      'arrivalTime': route.arrivalTime,
      'fare': _fareToJson(route.fare),
      'durationMinutes': route.durationMinutes,
      'stopsBetween': route.stopsBetween,
      'fromLatitude': route.fromLatitude,
      'fromLongitude': route.fromLongitude,
      'toLatitude': route.toLatitude,
      'toLongitude': route.toLongitude,
      'legs': route.legs.map(_legToJson).toList(),
      'routeId': route.routeId,
    };
  }

  Map<String, dynamic> _legToJson(TransitJourneyLeg leg) {
    return {
      'mode': leg.mode,
      'serviceName': leg.serviceName,
      'fromStopName': leg.fromStopName,
      'toStopName': leg.toStopName,
      'fromStopId': leg.fromStopId,
      'toStopId': leg.toStopId,
      'departureTime': leg.departureTime,
      'arrivalTime': leg.arrivalTime,
      'fare': _fareToJson(leg.fare),
      'durationMinutes': leg.durationMinutes,
      'stopsBetween': leg.stopsBetween,
      'fromLatitude': leg.fromLatitude,
      'fromLongitude': leg.fromLongitude,
      'toLatitude': leg.toLatitude,
      'toLongitude': leg.toLongitude,
      'passingStops': leg.passingStops,
      'passingStations': leg.passingStations.map(_stationToJson).toList(),
      'routeId': leg.routeId,
    };
  }

  Map<String, dynamic>? _fareToJson(TransitFare? fare) {
    if (fare == null) return null;
    return {
      'adult': fare.adult,
      'cash': fare.cash,
      'cashless': fare.cashless,
      'concession': fare.concession,
      'isZoneBased': fare.isZoneBased,
    };
  }

  Map<String, dynamic> _stationToJson(TransitStationPoint station) {
    return {
      'id': station.id,
      'name': station.name,
      'latitude': station.latitude,
      'longitude': station.longitude,
    };
  }

  TransitRouteResult? _routeFromJson(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      return _routeFromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  TransitRouteResult? _routeFromMap(Map<String, dynamic> data) {
    final fromStopName = _jsonText(data['fromStopName']);
    final toStopName = _jsonText(data['toStopName']);
    final serviceName = _jsonText(data['serviceName']);
    final mode = _jsonText(data['mode']);
    final departureTime = _jsonText(data['departureTime']);
    final arrivalTime = _jsonText(data['arrivalTime']);
    final durationMinutes = _jsonInt(data['durationMinutes']);
    final stopsBetween = _jsonInt(data['stopsBetween']);
    final fromLatitude = _jsonDouble(data['fromLatitude']);
    final fromLongitude = _jsonDouble(data['fromLongitude']);
    final toLatitude = _jsonDouble(data['toLatitude']);
    final toLongitude = _jsonDouble(data['toLongitude']);
    if (fromStopName == null ||
        toStopName == null ||
        serviceName == null ||
        mode == null ||
        departureTime == null ||
        arrivalTime == null ||
        durationMinutes == null ||
        stopsBetween == null ||
        fromLatitude == null ||
        fromLongitude == null ||
        toLatitude == null ||
        toLongitude == null) {
      return null;
    }

    final legs = <TransitJourneyLeg>[];
    final encodedLegs = data['legs'];
    if (encodedLegs is List) {
      for (final encodedLeg in encodedLegs) {
        if (encodedLeg is! Map<String, dynamic>) continue;
        final leg = _legFromMap(encodedLeg);
        if (leg != null) legs.add(leg);
      }
    }

    return TransitRouteResult(
      fromStopName: fromStopName,
      toStopName: toStopName,
      fromStopId: _jsonText(data['fromStopId']) ?? '',
      toStopId: _jsonText(data['toStopId']) ?? '',
      serviceName: serviceName,
      mode: mode,
      departureTime: departureTime,
      arrivalTime: arrivalTime,
      fare: _fareFromJson(data['fare']),
      durationMinutes: durationMinutes,
      stopsBetween: stopsBetween,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      legs: legs,
      routeId: _jsonText(data['routeId']),
    );
  }

  TransitJourneyLeg? _legFromMap(Map<String, dynamic> data) {
    final mode = _jsonText(data['mode']);
    final serviceName = _jsonText(data['serviceName']);
    final fromStopName = _jsonText(data['fromStopName']);
    final toStopName = _jsonText(data['toStopName']);
    final departureTime = _jsonText(data['departureTime']);
    final arrivalTime = _jsonText(data['arrivalTime']);
    final durationMinutes = _jsonInt(data['durationMinutes']);
    final stopsBetween = _jsonInt(data['stopsBetween']);
    final fromLatitude = _jsonDouble(data['fromLatitude']);
    final fromLongitude = _jsonDouble(data['fromLongitude']);
    final toLatitude = _jsonDouble(data['toLatitude']);
    final toLongitude = _jsonDouble(data['toLongitude']);
    if (mode == null ||
        serviceName == null ||
        fromStopName == null ||
        toStopName == null ||
        departureTime == null ||
        arrivalTime == null ||
        durationMinutes == null ||
        stopsBetween == null ||
        fromLatitude == null ||
        fromLongitude == null ||
        toLatitude == null ||
        toLongitude == null) {
      return null;
    }

    final passingStops = data['passingStops'] is List
        ? (data['passingStops'] as List).map((stop) => stop.toString()).toList()
        : const <String>[];
    final passingStations = <TransitStationPoint>[];
    final encodedStations = data['passingStations'];
    if (encodedStations is List) {
      for (final encodedStation in encodedStations) {
        if (encodedStation is! Map<String, dynamic>) continue;
        final station = _stationFromMap(encodedStation);
        if (station != null) passingStations.add(station);
      }
    }

    return TransitJourneyLeg(
      mode: mode,
      serviceName: serviceName,
      fromStopName: fromStopName,
      toStopName: toStopName,
      fromStopId: _jsonText(data['fromStopId']) ?? '',
      toStopId: _jsonText(data['toStopId']) ?? '',
      departureTime: departureTime,
      arrivalTime: arrivalTime,
      fare: _fareFromJson(data['fare']),
      durationMinutes: durationMinutes,
      stopsBetween: stopsBetween,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      passingStops: passingStops,
      passingStations: passingStations,
      routeId: _jsonText(data['routeId']),
    );
  }

  TransitFare? _fareFromJson(dynamic encodedFare) {
    if (encodedFare is! Map<String, dynamic>) return null;
    return TransitFare(
      adult: _jsonText(encodedFare['adult']) ?? '',
      cash: _jsonText(encodedFare['cash']) ?? '',
      cashless: _jsonText(encodedFare['cashless']) ?? '',
      concession: _jsonText(encodedFare['concession']) ?? '',
      isZoneBased: encodedFare['isZoneBased'] == true,
    );
  }

  TransitStationPoint? _stationFromMap(Map<String, dynamic> data) {
    final id = _jsonText(data['id']);
    final name = _jsonText(data['name']);
    final latitude = _jsonDouble(data['latitude']);
    final longitude = _jsonDouble(data['longitude']);
    if (id == null || name == null || latitude == null || longitude == null) {
      return null;
    }
    return TransitStationPoint(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
    );
  }

  String? _jsonText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _jsonInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _jsonDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  @override
  void dispose() {
    _transitDataService.dispose();
    _realtimeTransitService.dispose();
    _journeyPollingTimer?.cancel();
    _realtimeTransitTimer?.cancel();
    unawaited(_locationService.stopTracking());
    super.dispose();
  }
}
